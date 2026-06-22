# EC DynamoDB 整合性回復フロー

## 目的と不変条件

この文書は、checkout の Aurora commit 後に行う DynamoDB の副次データ更新と、失敗・TTL・
不整合からの回復手順を定義する。対象は `OrderLookup`、`ShoppingCart`、
`CustomerActivity` である。

- Aurora の `orders` と `payments` は source of truth であり、DynamoDB の状態だけで
  注文・決済の存在、状態、または権限を判断しない。
- DynamoDB の更新失敗は Aurora transaction の失敗理由にしない。Aurora commit 後の失敗は
  補償 rollback ではなく、Aurora を読み直す forward fix で回復する。
- lookup の解決結果を使う処理は、DynamoDB から得た ID で Aurora の row を取得し、元の
  `lookup_key` と一致することを検証してから結果を返す。DynamoDB の item 単独を
  認可・決済・注文状態の判断に使わない。
- `ShoppingCart` と `CustomerActivity` の消失は注文・決済の整合性を壊してはならない。

## OrderLookup の item 契約

`OrderLookup` は一つの `lookup_key` に一つの Aurora row を対応付ける。lookup key と
Aurora 側の一意制約は次の対応とする。

| lookup_key | Aurora の正規化 query | item の target |
| --- | --- | --- |
| `ORDER#<order_number>` | `orders.order_number = <order_number>` | `target_type = order`, `target_id = orders.id` |
| `PAYMENT#<provider>#<provider_payment_id>` | `payments.provider = <provider>` かつ `payments.provider_payment_id = <provider_payment_id>` | `target_type = payment`, `target_id = payments.id` |

item には少なくとも `lookup_key`、`target_type`、`target_id`、`cache_written_at_epoch`、
`expires_at_epoch` を保存する。`target_id` は Aurora の ID を十進文字列で保存する。item に
注文状態、決済状態、金額、顧客情報などの複製は置かない。`expires_at_epoch` は書込み時刻から
30 日後とする。

`orders.order_number` と `payments(provider, provider_payment_id)` は Aurora の unique
constraint で一意であるため、正規化 query が返す mapping は不変として扱う。item に異なる
target が既にある場合は、DynamoDB を正とせず Aurora の結果で置き換える。その事象は cache
破損または実装不備として記録・監視する。

## Aurora commit 後の非同期生成

### 永続的な起点

checkout の Aurora transaction 内で、`orders` と `payments` を作成した後に、同じ transaction
で OrderLookup 用の durable outbox record を作成する。実装時は専用 outbox table または同等の
永続キューを Aurora migration として追加する。DynamoDB への直接書込み、または commit 前の
publish は行わない。

outbox record は少なくとも次を持つ。

- `event_id`: 一意なイベント ID
- `event_type`: `order_lookup_upsert`
- `lookup_key`、`target_type`、`target_id`: 作成対象の mapping
- `status`、`attempt_count`、`next_attempt_at`、`completed_at`: 配送と再試行の状態

`lookup_key` ごとの一意性を持たせるか、同じ `event_id` を worker が重複処理しても同じ結果に
なるようにする。checkout で order と payment の両方が作られる場合は、それぞれの lookup key
に対する record を作る。

commit 後の worker は未完了 record を claim し、Aurora を ID と lookup key の両方で読み直して
正規 mapping を確認してから `OrderLookup` を upsert する。DynamoDB への書込み成功後にだけ
outbox record を完了にする。worker がその間に停止しても、次の実行は同じ mapping を再度
書くだけなので安全である。

```text
Aurora transaction:
  create orders / payments / inventory records
  insert order_lookup_outbox records
  commit

worker:
  claim pending outbox record
  canonical = read Aurora by target_id and lookup_key
  if canonical exists:
    conditionally upsert OrderLookup(canonical)
  mark outbox record completed
```

Aurora commit 済みの注文を lookup 作成失敗で rollback しない。commit 後の Aurora transaction は
既に確定しており、在庫引当、決済記録、外部 provider authorization を含む注文だけを取り消すと、
lookup 欠損より大きい整合性問題を作るためである。DynamoDB は再生成可能であり、失敗時は
outbox の再試行、後述のオンデマンド回復、定期照合で収束させる。

再試行可能な失敗（timeout、throttling、一時的な権限・接続障害）は指数バックオフに jitter を
加え、上限を設けて再試行する。試行上限を超えた record は削除せず `retry_exhausted` として
alert の対象にする。復旧後は同じ record を再投入または再実行できるようにする。

## lookup の読み取りと再生成

### 入力・出力

`ResolveOrderLookup` の入力は `lookup_key` とし、許可する接頭辞・構文を検証する。出力は
次のいずれかである。

- `found`: `target_type`、`target_id`、Aurora から取得・検証済みの対象 row
- `not_found`: Aurora に対応する row が存在しない
- `invalid_key`: key の構文が不正
- `retryable_error`: Aurora または DynamoDB の一時障害

Aurora に存在しないことを確認する前に `not_found` を返してはならない。negative cache は作らない。

### cache miss と不整合の回復手順

1. DynamoDB を `lookup_key` で `GetItem` する。item がない、TTL を過ぎている、
   `target_type`/`target_id` が欠ける場合は cache miss とする。
2. hit の場合も、item の target ID で Aurora row を取得し、row から再構成した `lookup_key` が
   入力値と一致するか確認する。不一致または row 不在は cache 不整合とする。
3. miss または不整合では、入力 key から決まる正規化 query を Aurora に実行する。0 件なら
   `not_found` を返す。1 件なら正規 mapping を出力する。Aurora の一意制約に反する複数件は
   cache では隠さず、処理を失敗させて alert する。
4. 正規 mapping を `OrderLookup` に条件付きで書く。item がない場合は作成する。同じ target の
   item がある場合は TTL と書込み時刻を更新する。異なる target の item がある場合は、読み取った
   既存 target を条件に compare-and-swap で Aurora の正規 mapping へ置換する。競合したら
   DynamoDB と Aurora を読み直して再判定する。
5. DynamoDB の再書込みに失敗しても、Aurora から得た `found` は返してよい。失敗は outbox または
   監視対象へ記録し、次回の読み取りまたは定期照合で再試行する。

```text
resolve(key):
  validate key
  cached = GetItem(key)
  if cached is structurally valid:
    source = get Aurora row by cached.target_id
    if source matches key:
      return found(source)

  canonical = query Aurora by key
  if canonical is absent:
    return not_found
  conditionally upsert canonical mapping into OrderLookup
  return found(canonical)
```

この手順の冪等性は、同じ `lookup_key` が Aurora の同じ一意な row を返すことと、同じ
mapping の upsert が item の値を変えず TTL を延長するだけであることで成立する。異なる target
への置換は、Aurora の正規 mapping と直前に観測した古い target の両方を条件にするため、古い
worker が新しい修復結果を上書きしない。

### 定期照合と手動修復

オンデマンド修復だけに依存せず、outbox の未完了・`retry_exhausted` record と、直近 30 日に
作成または更新された Aurora の `orders`/`payments` を keyset pagination で定期走査する。
各 source row から正規 key と target を再構成し、上記と同じ条件付き upsert を実行する。

入力は `source_type`、開始 cursor、終了 cursor または対象期間、dry-run の有無とする。出力は
走査件数、作成数、TTL 更新数、修復数、不変条件違反数、失敗 key の一覧とする。dry-run は
Aurora と DynamoDB を比較するだけで書き込まない。cursor と結果を記録し、途中再開できるようにする。
全件 scan や DynamoDB 側を起点にした正誤判定は行わない。

## ShoppingCart の checkout 後処理

採用する方式は、checkout に使った item だけを条件付きで削除する方式とする。`checked_out`
状態の item を残すと、現在のカート一覧 query が履歴 item も読み、TTL まで不要な read/storage を
負担するためである。注文履歴は Aurora の `orders` を読む。

checkout 開始時に、アプリケーションはカート snapshot として各 `item_id`、数量、
`cart_revision` を保持する。`cart_revision` は item の内容を変更するたびに増やす属性とする。
checkout の Aurora transaction 内で、同じ durable outbox に `cart_finalize` record（`order_id`、
`cart_owner_id`、snapshot の item ID と revision）を作る。commit 後の初回は同期的に後処理を
試みてよいが、完了判定は worker の再試行可能な record に委ねる。

worker は snapshot item ごとに、`cart_revision = snapshot_revision` の場合だけ
`DeleteItem` する。DynamoDB transaction の上限を超えるカートは 25 item 以下の chunk に分ける。
既に存在しない item は前回の成功または TTL による消失として成功扱いにする。revision が違う item は
checkout 後に利用者が変更した可能性があるため削除せず `skipped_changed` と記録して完了する。
これにより、commit 後に追加・変更されたカート内容を古い checkout が消さない。

- timeout、throttling、chunk の未完了は `cart_finalize` record を指数バックオフと jitter で再試行する。
- worker 停止後の再実行は、削除済み item を成功扱いにするため冪等である。
- 条件不成立は retry して解決しない業務上の変更であり、削除せず完了として監査する。
- カート後処理の失敗で注文、在庫引当、決済を rollback・取消ししない。注文は Aurora で確定済みであり、
  カートは再試行可能な UI 補助データだからである。

## CustomerActivity の保持と失効

`CustomerActivity` は閲覧・検索などの補助的な時系列 record であり、注文状態や認可の source of
truth にはしない。保持期間は event の `occurred_at` から 30 日とし、書込み時に
`expires_at_epoch = occurred_at + 30 days` を設定する。再読や表示で TTL を延長しない。すでに
失効時刻を過ぎた遅延 event は書き込まない。

DynamoDB TTL の物理削除は指定時刻に即時ではないため、読み取り側は `expires_at_epoch > now` の
item だけを表示対象にする。TTL により消えた activity は期待どおりの失効であり、Aurora から
再生成しない。分析・監査でより長い保持が必要になった場合は、TTL 前に Streams または export で
別の分析用保存先へ送る設計を追加する。`CustomerActivity` の table scan や期限切れ item の復元で
代替しない。

## 運用上の観測項目

- outbox の pending 件数、最古の滞留時間、retry exhausted 件数
- lookup 解決の cache miss 数、Aurora fallback 数、不整合修復数、CAS 競合数
- cart finalize の retry 件数、削除数、`skipped_changed` 件数
- CustomerActivity の期限切れ item がアプリケーションから除外されていること

これらのアラートは DynamoDB の一時障害を checkout 失敗として利用者へ返すためではなく、Aurora
を source of truth とした非同期収束が滞留していることを検知するために使う。

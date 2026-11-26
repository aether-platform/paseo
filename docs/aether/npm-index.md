# Aether fork 版 @getpaseo/* の配布先（Index の npm 面）— 消費側設定と発行手順

このファイルは fork 版 Paseo（`0.15.4-aether.N`）を **使う側** の設定と、**出す側** の手順の正本。
Index 全体の案内（`~/.config/aether-index/README.md`）は Python 面のみで npm 面の記述が無いため、ここに置く（D-11）。

## 1. 消費側（install する側）

| 項目 | 値 |
|---|---|
| レジストリ | `http://index.fleet.internal:4873/`（Index の Verdaccio。lab 内の名前解決で 192.168.210.252） |
| 認証 | 読み取りは不要（資格なしの npmrc で `npm view`／`npm install` が通ることを 2026-11-12 に確認） |
| スコープ | `@getpaseo` をこのレジストリに向ける。上流（npmjs）への中継もこのレジストリが行う |
| 版の指定 | **完全一致で固定**（例 `"@getpaseo/cli": "0.15.4-aether.1"`）。`latest` は上流の版のままなので、範囲指定や `latest` では fork 版にならない |
| dist-tag | fork 版には `aether` を付ける（`npm view @getpaseo/cli dist-tags.aether`） |

最小の `.npmrc`:

```ini
registry=http://index.fleet.internal:4873/
@getpaseo:registry=http://index.fleet.internal:4873/
```

Docker ビルドでは build-arg で渡す（term-image `Dockerfile.paseo` の形）:

```dockerfile
ARG NPM_REGISTRY=http://index.fleet.internal:4873/
RUN npm config set registry "${NPM_REGISTRY}" && npm ci
```

確認:
- `package-lock.json` の `resolved` が全件 `http://index.fleet.internal:4873/` であること
- `npm ls @getpaseo/server` が fork 版（`-aether.N`）に解決すること（cli は server に完全一致で依存する）

注意: 発行用の資格ファイルでは registry が IP 表記（`http://192.168.210.252:4873`）になっている。消費側は名前（`index.fleet.internal`）で書く。字面が違うので、突き合わせは名前解決で行う。

## 2. 発行側

`scripts/aether/publish-to-index-verdaccio.sh` を使う（依存順 highlight → relay → protocol → client → plugin → server → cli）。

- 失敗したらその場で止まり、後続は出さない（D-12。以前は server の失敗後に cli だけ載り、install が解決しない組が残った）
- 登録済みの版は飛ばすので、失敗の原因を直したら同じコマンドで再実行すればよい
- 発行前に全 tgz の中身（name@version）・`SHA512SUMS.txt`・要求本文の大きさを検査し、一つでも落ちたら何も出さない
- dist-tag は `aether`。`latest` は使わない（上流の版を上書きしない）
- 公開 npm には出さない（registry を一時 npmrc とコマンド行の両方で Index に固定）

```sh
NPM_TOKEN=<発行用トークン> scripts/aether/publish-to-index-verdaccio.sh <tgz のディレクトリ>   # 版は packages/server/package.json から
DRY_RUN=1 scripts/aether/publish-to-index-verdaccio.sh <tgz のディレクトリ>                 # 検査だけ
```

## 3. 受信上限（監視の注記）

- Index の Verdaccio は `max_body_size: 32mb`（2026-11-12、判断 J-4 で既定 10mb から引き上げ）
- `npm publish` は tgz を base64 で JSON に入れるので、要求本文は tgz の約 4/3 倍。`@getpaseo/server` は Web UI を同梱していて 0.15.4-aether.1 で tgz 17.0MB（本文 約 23MB）。**tgz が 24MB を超えると再び 413 になる**
- 発行スクリプトは `MAX_BODY_MB`（既定 32）で事前に判定して止める。上限を変えたら `MAX_BODY_MB` も合わせる
- fork 版を上げるたびに server の tgz の大きさを見ること。上限に近づいたら、上限を上げる（基盤の判断）か Web UI を別配布にする（fork の方針判断）

# CP/M-80 v2.2 for Fujitsu FM-11

富士通FM-11向けのCP/M-80（CP/M 2.2）移植です。2D／2HDの起動用FDイメージおよびHDDイメージを、リポジトリ内のソースから生成できます。

## 動作環境

次の3種類のCPU構成に対応しています。

| CPU構成 | FDイメージ生成 | HDDイメージ生成 |
|---|---|---|
| 6809＋Z80カード | `make image` | `make imagehdd` |
| 8088＋Z80カード | `make image8088` | `make image8088-hdd` |
| NEC V20（8080エミュレーションモード） | `make imagev20` | `make imagev20-hdd` |

V20構成ではZ80カードは不要です。RAMは128 KiB以上を必要とし、62K CP/M（TPAは0100h～DBFFh）として動作します。ディスクキャッシュ用に16 KiBのRAMを使用します。

2D FDD、2HD FDDおよびMDC接続のHDDに対応しています。ドライブ文字は起動メディアによらず次のように固定されています。

| ドライブ | 接続先 |
|---|---|
| A:～D: | 2D FDD 0～3 |
| E:～H: | 2HD FDD 0～3 |
| I: | HDD 1台（ディスク全体） |

2D FDD 0から起動した場合はA:、2HD FDD 0から起動した場合はE:、HDDから起動した場合はI:が初期カレントドライブになります。

HDDはM2230B、M2231B、M2232B、M2233B、M2234B、M2235B、M2241B、M2242B、M2243Bに対応します。区画管理は行わず、HDD全体をCP/M用として利用します。BDOSのディスク相対レコード番号を24ビットに拡張し、8 MiBを超える領域へのアクセスに対応しています。

[FM-11エミュレータ](https://github.com/sueyasu/fm11-emulator)で動作を確認していますが、実機での全構成・全モデルの動作は未確認です。

## ビルド

asm8080、LWTOOLSのlwasm、Python 3、GNU Makeが必要です。8088＋Z80版およびV20版の生成にはNASMも必要です。

```sh
make
make image8088
make imagev20
```

各FDイメージはD88形式とRAW形式で `build/images/` に生成されます。HDDイメージの生成時はモデルを指定できます。

```sh
make imagehdd HDD_MODEL=m2233b
make image8088-hdd HDD_MODEL=m2233b
make imagev20-hdd HDD_MODEL=m2233b
```

既存のHDDイメージは上書きしません。標準コマンドなどのCOMファイルは `external/commands/` に用意すると、イメージの生成時にユーザー領域0に収録されます。

詳しい手順は [docs/build.md](docs/build.md)、[docs/8088-z80.md](docs/8088-z80.md)、[docs/v20.md](docs/v20.md)、[docs/boot-hdd.md](docs/boot-hdd.md) を参照してください。

## コンソール

標準ではFM-11のキーボードと画面を使用します。RS-232C（USART0）に接続したシリアル端末でも利用できます。

CP/MのSTATコマンドでコンソールを切り替えられます。

```
STAT CON:=CRT:
STAT CON:=TTY:
STAT CON:=UC1:
```

CRT:はローカルコンソール、TTY:はシリアル端末、UC1:は両方からの入力を受け付け、両方に出力します。UC1:では入力文字が混在することがあります。BAT:はTTY:と同じ動作になります。LIST出力、PUNCH出力、READER入力はUSART0を使用します。

ローカル画面はANSI/VT100の基本的なカーソル移動、画面・行消去、前景色、文字装飾などに対応しています。カーソルキーはANSI形式のエスケープシーケンスを返します。シリアル出力は変換せずそのまま送信します。

## 利用上の注意

処理高速化のため、ライトバック方式のディスクキャッシュを使用しています。電源を切ったりエミュレータを終了したりする前には、CCPのプロンプトでCtrl-Cを入力し、再度プロンプトが表示されるまで待つようにしてください（ウォームブート時に全キャッシュを書き戻します）。

ディスクを交換する場合は、**交換前にCtrl-Cを入力して書き戻しを完了し、交換後にもCtrl-Cを入力してBDOSのディスク管理情報を更新してください。** 交換後のCtrl-Cを実行するまでは、新しいディスクへのアクセスを避けてください。起動ディスクは起動中に取り外さないでください。HDDは稼働中に交換しないでください。

ウォームブート時にディスクI/Oやキャッシュの書き戻しに失敗した場合は、再試行が続きプロンプトに戻らないことがあります。強制的な再起動によって未書き戻しデータが失われる可能性があるため、再起動後はディスクの内容を確認してください。

SUBMITを使用するときは起動ドライブ上で実行してください。CCPは起動ドライブ上のバッチファイル（$$$.SUB）を処理します。例えばE:から起動した環境では、`E>SUBMIT A:TEST` のように指定できます。

標準CP/Mのユーティリティには大容量HDDを正しく扱えないものがあります。例えば、標準のSTAT.COMではM2243Bの空き容量表示が桁あふれします。詳細は [docs/hdd-data.md](docs/hdd-data.md) を参照してください。

## FORMAT.COM

FDおよびHDDのフォーマット用コマンドです。全CPU構成で同一のFORMAT.COMを使用できます。

```
FORMAT B:
```

のようにオプションなしで実行すると、CP/M用のデータディスクとして初期化します。A:～D:は2D、E:～H:は2HDとしてフォーマットします。

CP/Mを起動可能なFDを作成する場合には、/Sオプションを指定します。

```
FORMAT B: /S
```

/Lオプションを指定するとFDの低レベルフォーマットのみを実施します。

HDDを初期化する場合は次のように指定します。

```
FORMAT I:
FORMAT HDD /S
```

I:とHDDは同じ対象です。オプションなしでは予約シリンダとディレクトリを初期化し、/Sを指定すると起動用IPLとシステムも書き込みます。HDDの物理フォーマット（/L）には対応していません。

/Sは実際の起動ディスクからシステムを読み出します。対象メディアと現在のCPU構成に対応したIPLを選択します。一般ファイルは転送しません。起動ドライブとカレントドライブはフォーマットできません。

**FORMATを実行すると対象ディスク上の既存ファイルは失われます。** 実行前に対象ドライブを確認し、必要なデータのバックアップを取ってください。

FORMAT.COMの作成にはlwasmとNASMの両方が必要です。詳しくは [docs/FORMAT.md](docs/FORMAT.md) を参照してください。

## 利用ライセンス

自作部分（ブートコード、CBIOS、ネイティブI/Oサーバーおよび付属ユーティリティ）はMITライセンスを採用しています（[LICENSE](LICENSE)）。CP/MのCCP/BDOSおよびその派生部分のライセンスについては [LICENSE.CPM](LICENSE.CPM) を参照してください。

## diskdefs

cpmtoolsでRAWイメージを操作するためのディスク定義ファイル（[diskdefs](diskdefs)）を用意しています。2D、2HDおよびHDDの9モデルに対応しています。2HDは先頭面の128バイトセクタを含むパディングなしのRAW形式です。D88ファイルには直接使用できません。

```sh
cpmls -f fm11-cpm80-2d build/images/fm11-cpm80-2d.raw
cpmls -f fm11-cpm80-2hd build/images/fm11-cpm80-2hd.raw
cpmls -f fm11-cpm80-m2233b build/images/fm11-cpm80-6809-hdd.img
```

イメージをエミュレータとcpmtoolsで同時に書き換えないでください。

## 関連ドキュメント

- [ビルド手順](docs/build.md)
- [8088＋Z80版](docs/8088-z80.md)
- [V20版](docs/v20.md)
- [HDD起動](docs/boot-hdd.md)
- [HDDデータアクセスと制約](docs/hdd-data.md)
- [FORMAT.COM](docs/FORMAT.md)
- [I/Oプロトコル](docs/io-protocol.md)
- [物理ディスク操作API](docs/format-api.md)
- [FDイメージの構造](docs/disk-image.md)

# ai-transcription

[whisper.cpp](https://github.com/ggml-org/whisper.cpp)（Rust バインディング: [whisper-rs](https://codeberg.org/tazz4843/whisper-rs)）を用いて、**動画・音声ファイルを文字起こし**するコマンドラインツールです。

## 必要なもの

- **Rust**（2021 エディション、stable 想定）
- **ビルド用**: CMake、C++ コンパイラ、`clang`（`whisper-rs-sys` の bindgen 用。パッージ例: Debian/Ubuntu では `build-essential`, `cmake`, `clang`）
- **実行時**:
  - **FFmpeg**（`ffmpeg` コマンド。動画や mp3 など、16kHz 以外の形式を扱う場合に必須）
  - **Whisper モデル**（`ggml` / `.bin` 形式。例: [ggerganov/whisper.cpp 付属スクリプト](https://github.com/ggml-org/whisper.cpp) や Hugging Face の配布物から取得）

### 環境変数

| 変数 | 意味 |
|------|------|
| `FFMPEG_PATH` | 使用する `ffmpeg` 実行ファイルのフルパス（未設定時は `PATH` 上の `ffmpeg`） |

## ビルド

```bash
cargo build --release
```

実行ファイルは `target/release/ai-transcription` です。

### CPU でさらに高速化する場合

システムに OpenBLAS 等を入れ、依存クレートの `openblas` 機能を有効にできます（`Cargo.toml` 内のコメントを参照）。

## 使い方

```bash
# 言語を自動検出
./target/release/ai-transcription transcribe -m /path/to/ggml-base.bin input.mp4 -o out.txt

# 日本語を指定
./target/release/ai-transcription transcribe -m /path/to/model.bin input.wav --language ja

# 標準出力へ
./target/release/ai-transcription transcribe -m /path/to/model.bin interview.m4a
```

### サブコマンド: `transcribe`

| 引数 / オプション | 説明 |
|-------------------|------|
| `input` | 入力ファイル（WAV 以外は ffmpeg で 16kHz モノラルに変換） |
| `-m`, `--model` | Whisper のモデル `.bin` へのパス（必須） |
| `-o`, `--output` | 出力テキストのパス（省略時は標準出力） |
| `-l`, `--language` | 言語コード（`ja`, `en` 等）。`auto` または未指定で自動検出 |
| `-t`, `--threads` | 推論スレッド数。`0` なら CPU コア数に合わせて最大 8（既定: 0） |

### 内部で使われる入出力形式

- Whisper への入力は **16 kHz、モノラル、32 bit float PCM** です。
- 入力が 16kHz / 16bit / mono|stereo の PCM WAV のときは、FFmpeg なしで直接読めます。それ以外は **FFmpeg** で 16kHz モノラル s16le にリサンプルし、生 PCM を読み取ってから処理します（パイプ先は WAV コンテナにしない）。

### 補助スクリプト（言語・モデル既定・出力パス）

[scripts/transcribe-ja.sh](./scripts/transcribe-ja.sh) は、**入力と同じディレクトリ**に、**拡張子だけ `.txt` にしたファイル**を書き出します。表示名・既定モデルファイル名・バイナリ相対パス・言語は **スクリプト先頭の設定ブロック**（`_scriptDisplayName` / `_defaultModelBasename` 等）で変更できます（使わない候補はコメントのまま）。

```bash
./scripts/transcribe-ja.sh ファイル名.m4a
# → ファイル名と同じディレクトリに ファイル名.txt

# カレントディレクトリのすべての .m4a（シェルがパスに展開してから渡す）
./scripts/transcribe-ja.sh ./*.m4a

# モデルや実行ファイルのパスを変えたい場合
WHISPER_MODEL=/path/to/ggml-small.bin ./scripts/transcribe-ja.sh ./foo.m4a
WHISPER_BIN=/path/to/ai-transcription ./scripts/transcribe-ja.sh ./foo.m4a
```

複数ファイルを渡した場合は**順に**処理し、**1件失敗しても次のファイルに進みます**。**すべて終わったあと、1件以上失敗があれば**終了コード 1 になります。マッチが0件のとき `./*.m4a` はシェル設定によっては文字列のまま渡ることがあるため、その場合は「ファイルが存在しません」で失敗扱いになります（その後の引数があれば続行）。

補助スクリプトの既定モデルはスクリプト内の `_defaultModelBasename`（例: `whisper.cpp/models/ggml-medium.bin`）。**ファイルが無い場合**、パスが `ggml-*.bin` 形式で、かつ同じディレクトリに `download-ggml-model.sh` があるとき、**ファイル名から推測したモデル ID**（例: `ggml-medium.bin` → `medium`）で自動取得を試みます（`curl` / `wget` / `wget2` のいずれかが必要）。任意名の `.bin` や、取得スクリプトと別ディレクトリに置く場合は手動で配置するか `WHISPER_MODEL` で既存ファイルを指定してください。

## GitHub への push と大容量ファイル

GitHub は **単一ファイル 100MB 超**を拒否します（[公式ドキュメント](https://docs.github.com/repositories/working-with-files/managing-large-files/about-large-files-on-github)）。動画（`.mp4` 等）や長時間の `.m4a` をコミットに含めると push が失敗します。

- 本リポジトリの `.gitignore` では、誤コミット防止のため **`*.mp4` / `*.m4a` / `*.mov` / `*.mkv`** を追跡対象外にしています。共有したい場合は [Git LFS](https://git-lfs.github.com/) の利用や、別ストレージ・リンクでの配布を検討してください。
- すでに履歴に含めてしまった場合は、`git filter-branch` や [git-filter-repo](https://github.com/newren/git-filter-repo) で該当ファイルを履歴から除去してから再度 push します（リモート未反映の履歴なら書き換えて問題ありません）。

## 仕様の詳細

[SPECIFICATION.md](./SPECIFICATION.md) を参照してください。

## ライセンス

MIT License（`Cargo.toml` の `license` 欄に準拠）

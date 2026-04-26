# 仕様書（ai-transcription）

## 1. 目的

動画・音声ファイルからテキストを取得する CLI を提供する。推論エンジンは **whisper.cpp**（Rust からは **whisper-rs 0.16** 経由）を用いる。

## 2. スコープ

| 項目 | 内容 |
|------|------|
| 入力 | ローカルファイル（ffmpeg がデコード可能な形式を想定） |
| 出力 | プレーンテキスト（1 行につき 1 セグメント。ファイルまたは標準出力） |
| 非スコープ | リアルタイムマイク入力、Web API、GUI |

## 3. 処理フロー

1. **入力解釈**  
   - 16kHz / 16bit / mono または stereo の PCM **WAV** として `hound` でオープン・仕様一致できる場合のみ直接読み込み、`whisper_rs` のユーティリティで f32 モノラル化する（`hound` がオープンできない m4a / mp3 等は **エラーにせず** FFmpeg 側へ回す）。  
   - 上記に当てはまらない場合は、**FFmpeg** を起動し、16kHz モノラル 16bit PCM の **生 s16le**（ヘッダなし、パイプ）を生成してから同様に f32 化する（パイプ WAV は RIFF 長不整合で失敗しやすいため）。
2. **モデル読み込み**  
   - `WhisperContext::new_with_params` にユーザー指定の `.bin` パスを渡す。`WhisperContextParameters` では `use_gpu: true` を指定（利用可能な場合は GPU を使用）。
3. **推論**  
   - `WhisperState::full` に `FullParams`（Greedy `best_of: 1`）と f32 サンプル列を渡す。言語は CLI で指定、または自動検出。
4. **結果**  
   - `full_n_segments` と `get_segment` を用い、各セグメントの文字列を改行区切りで連結。前後の空白をトリム。  
   - 標準エラーに whisper.cpp の **タイミング** を出力（`print_timings`）。

## 4. コマンドライン仕様

- トップレベル: サブコマンド `transcribe`。
- 必須: 入力パス、`-m` / `--model`。
- オプション: `--output`、 `--language`、 `--threads`（0 で自動）。

## 5. エラー時の挙動

- 入力が開けない、FFmpeg 失敗、モデルが読めない、推論失敗のいずれかの場合、**非ゼロの終了コード**で終了し、`anyhow` により文脈付きメッセージを表示する（Rust の標準エラー出力）。

## 6. 依存とビルド

- **whisper-rs**: whisper.cpp のネイティブビルド（CMake）を行う。システムに C++ ビルド環境と `clang`（bindgen）が必要。
- **hound**: WAV 解析。
- **clap**: CLI パース。

## 7. 将来の拡張（未実装）

- VTT / SRT 形式への出力  
- タイムスタンプ付き行の整形  
- Vulkan/CUDA 等、クレート feature に合わせたビルドドキュメントの充実

## 8. 補助スクリプト（リポジトリ同梱）

| ファイル | 内容 |
|----------|------|
| `scripts/transcribe-ja.sh` | 第1引数以降の**各**メディアを順に `transcribe` し、**それぞれ入力と同一ディレクトリ**に `<ベース名>.txt` を出力する（例: `./scripts/transcribe-ja.sh ./*.m4a`）。1件失敗しても次へ進み、**全件終了後に1件以上失敗があれば**非ゼロで終了。`--language` はスクリプト先頭の `_languageCode`（既定 `ja`）。モデル既定ファイル名は `_defaultModelBasename`（例: `ggml-medium.bin`、スクリプト内で変更可）。参照先の `ggml-*.bin` が無い場合、**リポジトリ同梱**の `whisper.cpp/models/download-ggml-model.sh` を実行して、**モデルパスの親ディレクトリ**へ取得を試みる（`WHISPER_MODEL` で任意ディレクトリの `ggml-*.bin` を指定可能）。`WHISPER_MODEL` / `WHISPER_BIN` で上書き可。 |

- **whisper.cpp**: 本リポジトリ直下の `whisper.cpp` は **Git サブモジュール**（`.gitmodules` に `url` を記載する）。`git clone` 後に `git submodule update --init --recursive` で取得する。

## 9. リポジトリ方針（メディアファイル）

- 本プロジェクトのソース管理対象は **CLI・スクリプト・仕様書** とする。入力用の動画・音声はローカルに置き、原則 **Git にコミットしない**（`.gitignore` で `*.mp4` 等を除外）。
- GitHub は単一ファイル **100MB 超**を受け付けないため、誤ってコミットした場合は履歴から除去する必要がある（手順は [README.md](./README.md) の「GitHub への push と大容量ファイル」を参照）。

---

- [x] 初版: transcribe サブコマンド、FFmpeg フォールバック、README 連携
- [x] `scripts/transcribe-ja.sh`: 先頭設定ブロックで表示名・モデル・言語など変更可・出力パス自動
- [x] `scripts/transcribe-ja.sh`: 複数入力（例 `./*.m4a`）を順に処理・個別失敗時も次へ・最後に集計終了
- [x] `scripts/transcribe-ja.sh`: 既定 `ggml-*.bin` 未配置時に download-ggml-model.sh による自動取得

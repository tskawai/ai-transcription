#!/usr/bin/env bash
#
# 概要: 指定した音声・動画ファイルを文字起こしし、入力と同じディレクトリに
#       「同一ベース名 + .txt」を書き出す（言語は先頭の _languageCode、既定 ja）。
#
# 主な仕様:
#   - 第1引数: 入力ファイルパス（相対・絶対可）。m4a / mp3 / wav / mp4 など ffmpeg 対応形式。
#   - 出力パス: <入力のディレクトリ>/<入力のファイル名から最後の拡張子を除いた名前>.txt
#   - 言語: 既定は ja（下の _languageCode で変更。環境変数 WHISPER_MODEL / WHISPER_BIN は従来どおり）。
#
# 制限事項:
#   - 本スクリプトは bash 上で動作する。リポジトリルートはスクリプトの親ディレクトリから推定する。
#   - 既定モデルパスにファイルが無い場合はエラー終了する（WHISPER_MODEL で上書き可能）。

set -euo pipefail

# =============================================================================
# 設定（ここだけ編集すればよい）
# =============================================================================

# ヘルプ・エラー表示に使うスクリプト名（実ファイル名と揃えなくてもよい）
_scriptDisplayName='transcribe-ja.sh'
# _scriptDisplayName='文字起こし.sh'

# whisper.cpp/models/ 直下の既定モデルファイル名（WHISPER_MODEL 未設定時）
# _defaultModelBasename='ggml-large-v3-turbo.bin'
# _defaultModelBasename='ggml-base.bin'
# _defaultModelBasename='ggml-small.bin'
 _defaultModelBasename='ggml-medium.bin'
# _defaultModelBasename='ggml-large-v3.bin'


# リポジトリルートからの ai-transcription 相対パス（WHISPER_BIN 未設定時）
_binaryRelToRepoRoot='target/release/ai-transcription'
# _binaryRelToRepoRoot='target/debug/ai-transcription'

# transcribe に渡す言語コード
_languageCode='ja'
# _languageCode='en'
# _languageCode='auto'

# =============================================================================

_usage() {
  printf '%s\n' "使い方: ${_scriptDisplayName} <入力ファイル>" >&2
  printf '%s\n' "例: ${_scriptDisplayName} ./録音.m4a" >&2
  printf '%s\n' "環境変数 WHISPER_MODEL / WHISPER_BIN でモデルと実行ファイルを上書きできます。" >&2
}

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  _usage
  exit 1
fi

_script_dir="$(cd "$(dirname "$0")" && pwd)"
_repo_root="$(cd "${_script_dir}/.." && pwd)"

_input_raw="$1"
if [ ! -f "${_input_raw}" ]; then
  printf 'エラー: 入力ファイルが存在しません: %s\n' "${_input_raw}" >&2
  exit 1
fi

# 入力の絶対パス化（相対指定でも出力先が一意になるようにする）
if command -v realpath >/dev/null 2>&1; then
  _input="$(realpath "${_input_raw}")"
elif readlink -f / >/dev/null 2>&1; then
  _input="$(readlink -f "${_input_raw}")"
else
  _dir="$(cd "$(dirname "${_input_raw}")" && pwd)"
  _input="${_dir}/$(basename "${_input_raw}")"
fi

_out_dir="$(dirname "${_input}")"
_base="$(basename "${_input}")"
_stem="${_base%.*}"
_out_txt="${_out_dir}/${_stem}.txt"

_bin="${WHISPER_BIN:-${_repo_root}/${_binaryRelToRepoRoot}}"
_model="${WHISPER_MODEL:-${_repo_root}/whisper.cpp/models/${_defaultModelBasename}}"

if [ ! -f "${_bin}" ]; then
  printf 'エラー: ai-transcription が見つかりません: %s\n' "${_bin}" >&2
  printf '先に cargo build --release を実行するか、WHISPER_BIN を設定してください。\n' >&2
  exit 1
fi

if [ ! -f "${_model}" ]; then
  printf 'エラー: モデルファイルがありません: %s\n' "${_model}" >&2
  printf '例: whisper.cpp ディレクトリで bash ./models/download-ggml-model.sh large-v3-turbo\n' >&2
  printf 'または WHISPER_MODEL に別の .bin を指定してください。\n' >&2
  exit 1
fi

printf '入力: %s\n出力: %s\nモデル: %s\n' "${_input}" "${_out_txt}" "${_model}" >&2

exec "${_bin}" transcribe \
  -m "${_model}" \
  "${_input}" \
  --language "${_languageCode}" \
  -o "${_out_txt}"

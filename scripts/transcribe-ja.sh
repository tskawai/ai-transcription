#!/usr/bin/env bash
#
# 概要: 指定した音声・動画ファイルを文字起こしし、入力と同じディレクトリに
#       「同一ベース名 + .txt」を書き出す（言語は先頭の _languageCode、既定 ja）。
#
# 主な仕様:
#   - 引数: 入力ファイルパスを1つ以上（相対・絶対可）。m4a / mp3 / wav / mp4 など ffmpeg 対応形式。
#   - 複数指定時: 各ファイルを順に処理する。1件失敗しても次の引数の処理に進む。全件完了後、1件以上
#     失敗していれば非ゼロ、すべて成功なら 0 で終了する。
#   - 出力パス: <入力のディレクトリ>/<入力のファイル名から最後の拡張子を除いた名前>.txt
#   - 言語: 既定は ja（下の _languageCode で変更。環境変数 WHISPER_MODEL / WHISPER_BIN は従来どおり）。
#
# 制限事項:
#   - 本スクリプトは bash 上で動作する。リポジトリルートはスクリプトの親ディレクトリから推定する。
#   - 参照するモデルが無い場合、パスが ggml-*.bin 形式で、かつ同ディレクトリに
#     whisper.cpp の download-ggml-model.sh があるときは自動取得を試みる。それ以外は手動配置が必要。
#   - 自動取得には curl / wget / wget2 のいずれかが必要（download-ggml-model.sh に準拠）。

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
  printf '%s\n' "使い方: ${_scriptDisplayName} <入力ファイル> [<入力ファイル> ...]" >&2
  printf '%s\n' "例: ${_scriptDisplayName} ./録音.m4a" >&2
  printf '%s\n' "例: ${_scriptDisplayName} ./*.m4a" >&2
  printf '%s\n' "環境変数 WHISPER_MODEL / WHISPER_BIN でモデルと実行ファイルを上書きできます。" >&2
  printf '%s\n' "モデルが無い場合、ggml-*.bin 形式であれば whisper.cpp の download-ggml-model.sh で取得を試みます。" >&2
}

if [ "${1:-}" = "" ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  _usage
  exit 1
fi

_script_dir="$(cd "$(dirname "$0")" && pwd)"
_repo_root="$(cd "${_script_dir}/.." && pwd)"

_bin="${WHISPER_BIN:-${_repo_root}/${_binaryRelToRepoRoot}}"
_model="${WHISPER_MODEL:-${_repo_root}/whisper.cpp/models/${_defaultModelBasename}}"

# 指定パスの ggml モデルが無いとき、ファイル名（ggml-<id>.bin）に対応する ID で download-ggml-model.sh を実行する。
_ensureGgmlModel() {
  local _path="$1"
  if [ -f "${_path}" ]; then
    return 0
  fi
  local _base _id _dir _dl
  _base="$(basename "${_path}")"
  case "${_base}" in
    ggml-*.bin)
      _id="${_base#ggml-}"
      _id="${_id%.bin}"
      ;;
    *)
      printf 'エラー: モデルファイルがありません: %s\n' "${_path}" >&2
      printf '自動取得はファイル名が ggml-<モデル名>.bin の場合のみ（例: ggml-medium.bin）。\n' >&2
      printf '手動: bash whisper.cpp/models/download-ggml-model.sh <モデル名>\n' >&2
      printf 'または WHISPER_MODEL に存在する .bin へのパスを指定してください。\n' >&2
      return 1
      ;;
  esac
  _dir="$(dirname "${_path}")"
  _dl="${_dir}/download-ggml-model.sh"
  if [ ! -f "${_dl}" ]; then
    printf 'エラー: モデルファイルがありません: %s\n' "${_path}" >&2
    printf '自動取得には同じディレクトリに download-ggml-model.sh が必要です（%s）\n' "${_dl}" >&2
    printf '手動: bash whisper.cpp/models/download-ggml-model.sh %s\n' "${_id}" >&2
    return 1
  fi
  printf 'モデルが見つかりません。自動ダウンロードします（モデル ID: %s）...\n' "${_id}" >&2
  if ! bash "${_dl}" "${_id}" "${_dir}"; then
    printf 'エラー: モデルの自動ダウンロードに失敗しました: %s\n' "${_path}" >&2
    return 1
  fi
  if [ ! -f "${_path}" ]; then
    printf 'エラー: ダウンロード後もモデルファイルがありません: %s\n' "${_path}" >&2
    return 1
  fi
  return 0
}

if [ ! -f "${_bin}" ]; then
  printf 'エラー: ai-transcription が見つかりません: %s\n' "${_bin}" >&2
  printf '先に cargo build --release を実行するか、WHISPER_BIN を設定してください。\n' >&2
  exit 1
fi

if ! _ensureGgmlModel "${_model}"; then
  exit 1
fi

# 1 ファイル分の文字起こし。失敗時は 1、成功時は 0 を返す（呼び出し元がループで次へ進む）。
_transcribeOne() {
  local _input_raw="$1"
  local _input
  if [ ! -f "${_input_raw}" ]; then
    printf 'エラー: 入力ファイルが存在しません: %s\n' "${_input_raw}" >&2
    return 1
  fi

  if command -v realpath >/dev/null 2>&1; then
    _input="$(realpath "${_input_raw}")"
  elif readlink -f / >/dev/null 2>&1; then
    _input="$(readlink -f "${_input_raw}")"
  else
    local _dir
    _dir="$(cd "$(dirname "${_input_raw}")" && pwd)"
    _input="${_dir}/$(basename "${_input_raw}")"
  fi

  local _out_dir _base _stem _out_txt
  _out_dir="$(dirname "${_input}")"
  _base="$(basename "${_input}")"
  _stem="${_base%.*}"
  _out_txt="${_out_dir}/${_stem}.txt"

  printf '入力: %s\n出力: %s\nモデル: %s\n' "${_input}" "${_out_txt}" "${_model}" >&2

  "${_bin}" transcribe \
    -m "${_model}" \
    "${_input}" \
    --language "${_languageCode}" \
    -o "${_out_txt}"
}

# if の条件式内では set -e が失敗で止まらないため、1件失敗しても次のファイルへ進む
_exitAny=0
for _arg in "$@"; do
  if ! _transcribeOne "${_arg}"; then
    _exitAny=1
  fi
done
exit "${_exitAny}"

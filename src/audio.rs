//! 入力メディアを 16kHz モノラル f32 PCM（Whisper 入力）へ変換する。

use std::path::Path;
use std::process::Command;

use anyhow::{bail, Context, Result};
use whisper_rs::{convert_integer_to_float_audio, convert_stereo_to_mono_audio};

/// 期待するサンプリングレート（Whisper 仕様）
const WHISPER_SAMPLE_RATE: u32 = 16_000;

/// ffmpeg でメディアを 16kHz モノラル **生 s16le PCM**（ヘッダなし）にし、f32 モノラルに変換する。
///
/// パイプへ `-f wav` を使うと RIFF のデータ長が不正になり `hound` が失敗することがあるため、
/// `-f s16le` でリトルエンディアン 16bit 直列バイトのみ受け取り、自前で i16→f32 する。
pub fn load_pcm_f32_from_media(ffmpeg: &str, path: &Path) -> Result<Vec<f32>> {
    let out = Command::new(ffmpeg)
        .args([
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-i",
            &path.to_string_lossy(),
            "-vn",
            "-ar",
            "16000",
            "-ac",
            "1",
            "-acodec",
            "pcm_s16le",
            "-f",
            "s16le",
            "pipe:1",
        ])
        .output()
        .with_context(|| {
            format!(
                "コマンド実行に失敗しました: 関数 load_pcm_f32_from_media, 引数 path={path:?} ffmpeg={ffmpeg}"
            )
        })?;

    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        bail!(
            "ffmpeg のデコードに失敗しました: path={path:?}, 終了ステータス={:?}, stderr={stderr}",
            out.status.code()
        );
    }

    s16le_bytes_to_f32_mono(&out.stdout)
        .with_context(|| format!("s16le PCM の解釈に失敗: path={path:?}"))
}

/// 16kHz モノラル想定のリトルエンディアン s16 生バイト列を f32 サンプル列へ変換する。
fn s16le_bytes_to_f32_mono(bytes: &[u8]) -> Result<Vec<f32>> {
    if bytes.is_empty() {
        return Ok(Vec::new());
    }
    if bytes.len() % 2 != 0 {
        bail!(
            "s16le PCM のバイト長が 2 の倍数でありません: {} バイト",
            bytes.len()
        );
    }
    let n = bytes.len() / 2;
    let mut samples_i16 = Vec::with_capacity(n);
    for chunk in bytes.chunks_exact(2) {
        samples_i16.push(i16::from_le_bytes([chunk[0], chunk[1]]));
    }
    let mut f32s = vec![0.0f32; n];
    convert_integer_to_float_audio(&samples_i16, &mut f32s)
        .map_err(|e| anyhow::anyhow!("i16→f32 変換失敗: {e}"))?;
    Ok(f32s)
}

/// 16kHz / 16bit / mono または stereo の WAV を f32 モノに読み込む。形式が合わない場合は None。
///
/// m4a / mp3 など **WAV 以外**は `hound` が RIFF ヘッダを要求するためオープンに失敗する。
/// その場合はエラーにせず `None` を返し、呼び出し側で ffmpeg 経路にフォールバックする。
pub fn try_load_wav_f32(path: &Path) -> Result<Option<Vec<f32>>> {
    let mut r = match hound::WavReader::open(path) {
        Ok(reader) => reader,
        Err(_) => return Ok(None),
    };
    let spec = r.spec();
    if spec.sample_format != hound::SampleFormat::Int || spec.sample_rate != WHISPER_SAMPLE_RATE {
        return Ok(None);
    }
    if spec.bits_per_sample != 16 {
        return Ok(None);
    }

    if spec.channels == 1 {
        let samples: Vec<i16> = r.samples().collect::<Result<_, _>>()?;
        let mut f32s = vec![0.0f32; samples.len()];
        convert_integer_to_float_audio(&samples, &mut f32s)
            .map_err(|e| anyhow::anyhow!("i16→f32 変換失敗: {e}"))?;
        return Ok(Some(f32s));
    }

    if spec.channels == 2 {
        let samples: Vec<i16> = r.samples().collect::<Result<_, _>>()?;
        let mut f32_stereo = vec![0.0f32; samples.len()];
        convert_integer_to_float_audio(&samples, &mut f32_stereo)
            .map_err(|e| anyhow::anyhow!("i16→f32 変換失敗: {e}"))?;
        let mut f32_mono = vec![0.0f32; samples.len() / 2];
        convert_stereo_to_mono_audio(&f32_stereo, &mut f32_mono)
            .map_err(|e| anyhow::anyhow!("stereo→mono 変換失敗: {e}"))?;
        return Ok(Some(f32_mono));
    }

    Ok(None)
}

/// PATH 上の `ffmpeg` を解決（なければ "ffmpeg"）
pub fn resolve_ffmpeg() -> String {
    if let Some(p) = std::env::var_os("FFMPEG_PATH") {
        let s = p.to_string_lossy().to_string();
        if !s.is_empty() {
            return s;
        }
    }
    "ffmpeg".to_string()
}

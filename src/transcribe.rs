//! whisper-rs を用いた推論と結果の書き出し。

use std::fs;
use std::io::Write;
use std::path::Path;

use anyhow::{bail, Context, Result};
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

use crate::audio;

/// 文字起こしのメイン処理
pub fn run_transcribe(
    input: &Path,
    model: &Path,
    output: Option<&Path>,
    language: Option<String>,
    threads: usize,
) -> Result<()> {
    let ffmpeg = audio::resolve_ffmpeg();

    // 1) 16kHz f32 モノラルへ
    let samples = if let Some(s) = audio::try_load_wav_f32(input).with_context(|| {
        format!(
            "事前チェック: 関数 run_transcribe, 引数 input={input:?} model={model:?}"
        )
    })? {
        s
    } else {
        audio::load_pcm_f32_from_media(&ffmpeg, input).with_context(|| {
            format!(
                "ffmpeg 経由の読み込みに失敗: input={input:?}。16kHz モノラル 16bit WAV か、ffmpeg を利用できる形式にしてください"
            )
        })?
    };

    if samples.is_empty() {
        bail!("入力音声の長さが 0 です: input={input:?}");
    }

    // 2) モデル読み込み
    let ctx_params = WhisperContextParameters {
        use_gpu: true,
        ..Default::default()
    };

    let ctx = WhisperContext::new_with_params(model, ctx_params)
        .with_context(|| format!("モデル読み込み失敗: model={model:?}"))?;
    let mut state = ctx
        .create_state()
        .with_context(|| "Whisper 状態 create_state 失敗")?;

    // 3) デコード
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    let n_threads = if threads == 0 {
        std::thread::available_parallelism()
            .map(|n| n.get().min(8) as i32)
            .unwrap_or(4)
    } else {
        threads as i32
    };
    params.set_n_threads(n_threads);
    params.set_print_progress(true);
    params.set_print_realtime(false);

    match &language {
        None => {
            params.set_detect_language(true);
        }
        Some(s) if s.eq_ignore_ascii_case("auto") => {
            params.set_detect_language(true);
        }
        Some(s) => {
            params.set_language(Some(s.as_str()));
        }
    }

    state
        .full(params, &samples)
        .with_context(|| "whisper 推論 (full) が失敗")?;

    let n = state.full_n_segments();
    let mut lines: Vec<String> = Vec::new();
    for i in 0..n {
        if let Some(seg) = state.get_segment(i) {
            let t = seg.to_str_lossy().with_context(|| "セグメント文字列取得失敗")?;
            lines.push(t.trim().to_string());
        }
    }
    let text = lines
        .join("\n")
        .trim()
        .to_string();

    if let Some(path) = output {
        let mut f = fs::File::create(path)
            .with_context(|| format!("出力ファイルを作成できません: output={path:?}"))?;
        f.write_all(text.as_bytes())
            .with_context(|| format!("出力ファイル書き込み失敗: output={path:?}"))?;
    } else {
        println!("{text}");
    }

    ctx.print_timings();
    Ok(())
}

//! 動画・音声ファイルを OpenAI Whisper（whisper.cpp 経由）で文字起こしする CLI エントリ。

mod audio;
mod transcribe;

use std::path::PathBuf;

use anyhow::Result;
use clap::{Parser, Subcommand};

/// whisper.cpp バインディング（whisper-rs）を用いた文字起こしツール
#[derive(Parser, Debug)]
#[command(name = "ai-transcription", version, about)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// 音声または動画から文字起こし
    Transcribe {
        /// 入力ファイル（wav / mp3 / m4a / mp4 など ffmpeg が扱える形式）
        input: PathBuf,
        /// Whisper の ggml モデル（.bin）へのパス
        #[arg(short = 'm', long)]
        model: PathBuf,
        /// 出力テキストファイル（未指定なら標準出力）
        #[arg(short, long)]
        output: Option<PathBuf>,
        /// 言語コード（例: ja, en）。未指定または auto で自動検出
        #[arg(short, long)]
        language: Option<String>,
        /// 推論スレッド数（0 でハードウェアに合わせる）
        #[arg(short = 't', long, default_value_t = 0)]
        threads: usize,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Commands::Transcribe {
            input,
            model,
            output,
            language,
            threads,
        } => transcribe::run_transcribe(&input, &model, output.as_deref(), language, threads),
    }
}

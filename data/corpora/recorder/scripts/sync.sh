#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: data/corpora/recorder/scripts/sync.sh <target> [source]

Targets:
  librispeech          download the public LibriSpeech smoke clips
  ami                  download AMI Mix-Headset audio and RTTM references
  extended-generated   generate short/noisy/VoIP clips from the LibriSpeech clip
  librivox             download the public Sherlock Holmes long-form clip
                       (explicit target; Archive.org sometimes returns 503)
  private-meetings     copy private meeting eval files from source
  all-public           librispeech, extended-generated, ami
  all                  all-public plus private-meetings if a source is configured

Private source resolution:
  source arg > PARLOQ_PRIVATE_RECORDINGS_DIR. No home-directory fallback is used.

Environment:
  PARLOQ_RECORDER_CORPUS_DIR overrides the destination corpus root.
USAGE
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
msg() { printf '==> %s\n' "$*" >&2; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
default_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
corpus_root=${PARLOQ_RECORDER_CORPUS_DIR:-$default_root}
downloads="$corpus_root/_downloads"

need() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

download() {
  local url=$1 out=$2
  mkdir -p "$(dirname -- "$out")"
  if [[ -s $out ]]; then
    msg "cached $(basename -- "$out")"
    return
  fi
  msg "download $url"
  curl -fL --retry 3 --retry-delay 2 -o "$out.part" "$url"
  mv "$out.part" "$out"
}

install_file() {
  local src=$1 dst=$2
  mkdir -p "$(dirname -- "$dst")"
  cp "$src" "$dst.part"
  chmod u+rw "$dst.part"
  mv -f "$dst.part" "$dst"
}

sync_librispeech() {
  need curl
  need tar
  local archive="$downloads/dev-clean.tar.gz"
  local extract="$downloads/librispeech-dev-clean"
  local out="$corpus_root/librispeech"
  download "https://www.openslr.org/resources/12/dev-clean.tar.gz" "$archive"
  mkdir -p "$extract" "$out"
  if [[ ! -f $extract/LibriSpeech/dev-clean/1272/128104/1272-128104-0000.flac ]]; then
    msg "extract LibriSpeech speaker 1272 chapter 128104"
    tar -xzf "$archive" -C "$extract" \
      LibriSpeech/dev-clean/1272/128104/1272-128104-0000.flac \
      LibriSpeech/dev-clean/1272/128104/1272-128104-0001.flac \
      LibriSpeech/dev-clean/1272/128104/1272-128104.trans.txt
  fi
  install_file "$extract/LibriSpeech/dev-clean/1272/128104/1272-128104-0000.flac" "$out/1272-128104-0000.flac"
  install_file "$extract/LibriSpeech/dev-clean/1272/128104/1272-128104-0001.flac" "$out/1272-128104-0001.flac"
  install_file "$extract/LibriSpeech/dev-clean/1272/128104/1272-128104.trans.txt" "$out/1272-128104.trans.txt"
  msg "librispeech ready: $out"
}

sync_ami() {
  need curl
  need git
  need ffmpeg
  local dest="$corpus_root/ami"
  local setup_repo="$downloads/AMI-diarization-setup"
  local mirror="http://groups.inf.ed.ac.uk/ami/AMICorpusMirror/amicorpus"
  local meetings=(ES2002a ES2004a IS1009a)
  mkdir -p "$dest/audio" "$dest/rttm" "$downloads"
  if [[ ! -d $setup_repo/.git ]]; then
    git clone --depth 1 https://github.com/pyannote/AMI-diarization-setup "$setup_repo"
  fi
  local m wav
  for m in "${meetings[@]}"; do
    wav="$downloads/$m.Mix-Headset.wav"
    if [[ ! -s $dest/audio/$m.flac ]]; then
      download "$mirror/$m/audio/$m.Mix-Headset.wav" "$wav"
      msg "convert $m to 16k mono FLAC"
      ffmpeg -hide_banner -loglevel error -y -i "$wav" \
        -ac 1 -ar 16000 -c:a flac "$dest/audio/$m.flac"
    fi
    find "$setup_repo" -name "$m.rttm" -exec cp {} "$dest/rttm/$m.rttm" \; -quit
    [[ -s $dest/rttm/$m.rttm ]] || die "missing RTTM for $m"
  done
  msg "ami ready: $dest"
}

write_ls_ref() {
  local src=$1 dst=$2
  mkdir -p "$(dirname -- "$dst")"
  awk '$1 == "1272-128104-0000" { sub($1 " ", ""); print; found=1 } END { exit found ? 0 : 1 }' \
    "$src" > "$dst"
}

sync_extended_generated() {
  need ffmpeg
  sync_librispeech
  local src="$corpus_root/librispeech/1272-128104-0000.flac"
  local trans="$corpus_root/librispeech/1272-128104.trans.txt"
  local short="$corpus_root/extended/short-dictation"
  local demand="$corpus_root/extended/demand"
  local zoom="$corpus_root/extended/zoom-sim"
  mkdir -p "$short" "$demand" "$zoom"
  write_ls_ref "$trans" "$short/ls_1272_0000.txt"
  cp "$short/ls_1272_0000.txt" "$demand/ls_1272_0000.txt"
  cp "$short/ls_1272_0000.txt" "$zoom/ls_1272_0000.txt"
  ffmpeg -hide_banner -loglevel error -y -i "$src" -t 5 \
    -ac 1 -ar 16000 -c:a flac "$short/ls_1272_0000_5s.flac"
  ffmpeg -hide_banner -loglevel error -y -i "$src" -t 15 \
    -ac 1 -ar 16000 -c:a flac "$short/ls_1272_0000_15s.flac"
  ffmpeg -hide_banner -loglevel error -y -i "$src" -t 30 \
    -ac 1 -ar 16000 -c:a flac "$short/ls_1272_0000_30s.flac"
  local snr
  for snr in 20 10 5; do
    ffmpeg -hide_banner -loglevel error -y -i "$src" \
      -filter_complex "anoisesrc=color=pink:amplitude=0.02:duration=30[noise];[0:a][noise]amix=inputs=2:duration=first:weights=1 $(awk -v s="$snr" 'BEGIN { printf "%.6f", 10^(-s/20) }')[out]" \
      -map '[out]' -ac 1 -ar 16000 -c:a flac "$demand/cafe_snr${snr}db.flac"
  done
  ffmpeg -hide_banner -loglevel error -y -i "$src" \
    -c:a libopus -b:a 32k -application voip "$downloads/ls_1272_0000_opus32k.ogg"
  ffmpeg -hide_banner -loglevel error -y -i "$downloads/ls_1272_0000_opus32k.ogg" \
    -ac 1 -ar 16000 -c:a flac "$zoom/ls_1272_0000_opus32k.flac"
  msg "extended generated clips ready: $corpus_root/extended"
}

sync_librivox() {
  need curl
  need ffmpeg
  local out="$corpus_root/extended/librivox-long"
  local mp3="$downloads/sherlock_01.mp3"
  mkdir -p "$out"
  download "https://archive.org/download/sherlock_holmes_librivox/adventures_of_sherlock_holmes_01_doyle_128kb.mp3" "$mp3"
  ffmpeg -hide_banner -loglevel error -y -i "$mp3" \
    -ac 1 -ar 16000 -c:a flac "$out/sherlock_01_full.flac"
  msg "librivox ready: $out"
}

copy_if_present() {
  local src=$1 dst=$2
  if [[ -f $src ]]; then
    mkdir -p "$(dirname -- "$dst")"
    cp "$src" "$dst"
    printf '  copied %s\n' "$dst" >&2
  else
    printf '  missing %s\n' "$src" >&2
  fi
}

sync_private_meetings() {
  local src=${1:-${PARLOQ_PRIVATE_RECORDINGS_DIR:-}}
  [[ -n $src ]] || die "private-meetings requires a source arg or PARLOQ_PRIVATE_RECORDINGS_DIR"
  [[ -d $src ]] || die "private source is not a directory: $src"
  local trimmed="$corpus_root/meeting-trimmed"
  local private="$corpus_root/private"
  local name
  for name in m1_2min m1_2min_off300 m1_2min_off600 m1_2min_off900; do
    copy_if_present "$src/meeting-trimmed/$name.flac" "$trimmed/$name.flac"
    copy_if_present "$src/meeting-trimmed/$name.offline-frozen.txt" "$trimmed/$name.offline-frozen.txt"
  done
  copy_if_present "$src/20260506-163338.flac" "$private/20260506-163338.flac"
  copy_if_present "$src/20260506-163338.offline-frozen.txt" "$private/20260506-163338.offline-frozen.txt"
  msg "private meeting import complete: $corpus_root"
}

target=${1:-}
case "$target" in
  -h|--help|help|'') usage; exit 0 ;;
  librispeech) sync_librispeech ;;
  ami) sync_ami ;;
  extended-generated) sync_extended_generated ;;
  librivox) sync_librivox ;;
  private-meetings) sync_private_meetings "${2:-}" ;;
  all-public)
    sync_librispeech
    sync_extended_generated
    sync_ami
    ;;
  all)
    sync_librispeech
    sync_extended_generated
    sync_ami
    if [[ -n ${2:-${PARLOQ_PRIVATE_RECORDINGS_DIR:-}} ]]; then
      sync_private_meetings "${2:-}"
    else
      msg "skip private meetings: no source configured"
    fi
    ;;
  *) die "unknown target: $target" ;;
esac

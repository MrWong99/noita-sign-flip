#!/usr/bin/env bash
# Runs the sign_flip probe mod (probe/) in an isolated Proton prefix: own saves, own mod list (sign_flip, the probe and,
# for the "fi" suite, Field Imbue). Your normal Noita prefix, saves and mod_config.xml are not touched.
# It waits until the probe logs DONE or ERROR (or TIMEOUT seconds pass), kills only this prefix's processes and copies
# the probe's lines to $OUT and the whole log to $OUT_LOG.
#   usage: tools/probe-run.sh [suite] [ids]
#     suite: main (default) | fi | fi-first (with Field Imbue after / before sign_flip)
#     ids: comma-separated modifier ids to limit the main sweep to
# Noita/logger.txt in the game folder is shared by every Noita instance, so this refuses to run next to another one.
# Needs the display and GPU (from Claude Code: run it outside the sandbox).
set -euo pipefail
STEAM="$HOME/.local/share/Steam"
NOITA="$STEAM/steamapps/common/Noita"
PROTON="${PROTON:-/usr/share/steam/compatibilitytools.d/proton-cachyos-native/proton}"
PREFIX="$(realpath -m -- "${PREFIX:-$HOME/noita-dev/prefix-signflip}")"
TIMEOUT="${TIMEOUT:-1200}"
OUT="${OUT:-$HOME/noita-dev/signflip-probe.txt}"
OUT_LOG="${OUT_LOG:-$HOME/noita-dev/signflip-logger.txt}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
FI_REPO="${FI_REPO:-$HOME/field_imbue}"
# the probe writes saves, a mod list and a config into the prefix: never into your own Noita's (Steam's compatdata)
case "$PREFIX/" in
"$(realpath -m -- "$STEAM")"/*)
	echo "PREFIX must not be inside Steam ($PREFIX)" >&2
	exit 2
	;;
esac
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM" STEAM_COMPAT_DATA_PATH="$PREFIX" SteamAppId=881100 SteamGameId=881100

# processes started in this prefix: Proton gives them WINEPREFIX=<prefix>/pfx/ (with the trailing slash)
in_prefix() {
	{ tr '\0' '\n' <"/proc/$1/environ"; } 2>/dev/null | grep -qxE "WINEPREFIX=$PREFIX/pfx/?"
}
prefix_pids() {
	for d in /proc/[0-9]*; do
		if in_prefix "${d#/proc/}"; then
			echo "${d#/proc/}"
		fi
	done
}
other_noita() {
	for pid in $(pgrep -f 'noita(_dev)?\.exe' || true); do
		if ! in_prefix "$pid"; then
			echo "$pid"
		fi
	done
}
if [ -n "$(other_noita)" ]; then
	echo "another Noita is running (it shares Noita/logger.txt): close it first" >&2
	exit 2
fi
if [ -n "$(prefix_pids)" ]; then
	echo "a probe Noita from an earlier run is still running in $PREFIX" >&2
	exit 2
fi

SUITE="${1:-main}"
case "$SUITE" in
main | fi | fi-first) ;;
*)
	echo "unknown suite '$SUITE' (main, fi, fi-first)" >&2
	exit 2
	;;
esac
TOKEN="$(date +%s)-$$"
mkdir -p "$PREFIX"
# Noita/mods/<name> must be this checkout, or the probe would test whatever is installed there
link_mod() { # <mod folder name> <checkout>
	local dst="$NOITA/mods/$1"
	if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
		ln -s "$2" "$dst"
	fi
	if [ "$(readlink -f "$dst")" != "$(readlink -f "$2")" ]; then
		echo "$dst is not $2: refusing to probe something else" >&2
		exit 2
	fi
}
link_mod sign_flip "$REPO"
if [ "$SUITE" != main ]; then
	link_mod field_imbue "$FI_REPO"
fi
# The probe mod is only linked while a run lasts: it rewrites the held wand, so it must never be enabled in a real run.
ln -sfn "$REPO/probe" "$NOITA/mods/sign_flip_probe"
trap 'rm -f "$NOITA/mods/sign_flip_probe" "$REPO/probe/suite.txt"' EXIT
printf '%s\n%s\n%s\n' "$SUITE" "${2:-}" "$TOKEN" >"$REPO/probe/suite.txt"
if [ ! -d "$PREFIX/pfx" ]; then
	"$PROTON" run cmd.exe /c exit || true
fi
SAVE="$PREFIX/pfx/drive_c/users/steamuser/AppData/LocalLow/Nolla_Games_Noita/save00"
# Start every run from an empty save00. Probe instances are killed, not quit, so a leftover autosave would bring up the
# "Looks like the game crashed? Restore" dialog. Only ever touches this probe prefix.
case "$SAVE" in
"$HOME"/noita-dev/*)
	if [ -e "$SAVE" ]; then
		gio trash "$SAVE"
	fi
	;;
*)
	echo "not clearing $SAVE (only prefixes under ~/noita-dev are cleared)" >&2
	;;
esac
mkdir -p "$SAVE"
# suite "fi": Field Imbue loads after sign_flip, "fi-first": before it (both mods wrap the same actions)
mod_line() {
	printf '  <Mod enabled="1" name="%s" settings_fold_open="0" workshop_item_id="0" >\n  </Mod>\n' "$1"
}
{
	echo "<Mods>"
	if [ "$SUITE" = "fi-first" ]; then mod_line field_imbue; fi
	mod_line sign_flip
	if [ "$SUITE" = "fi" ]; then mod_line field_imbue; fi
	mod_line sign_flip_probe
	echo "</Mods>"
} >"$SAVE/mod_config.xml"
# Copy your config once so a fresh profile skips the first-run release-notes dialog (it blocks -gamemode 0).
USER_CFG="$STEAM/steamapps/compatdata/881100/pfx/drive_c/users/steamuser/AppData/LocalLow/Nolla_Games_Noita/save_shared/config.xml"
if [ -f "$USER_CFG" ] && [ ! -f "$SAVE/../save_shared/config.xml" ]; then
	mkdir -p "$SAVE/../save_shared"
	cp "$USER_CFG" "$SAVE/../save_shared/config.xml"
fi
# keep simulating at full speed while the window is in the background (probe copy only): no pause on focus loss, and
# no vsync (a window hidden behind a fullscreen game gets no vblank and would crawl)
sed -i -e 's/application_pause_when_unfocused="1"/application_pause_when_unfocused="0"/' -e 's/vsync="[0-9]"/vsync="0"/' \
	"$SAVE/../save_shared/config.xml"

LOG="$NOITA/logger.txt"
cd "$NOITA"
"$PROTON" run "$NOITA/noita.exe" -no_logo_splashes -gamemode 0 -gamemode_mod_name -gamemode_mod_workshop_item_id 0 \
	-save_slot 0 -windowed >"$PREFIX/noita.out" 2>&1 &

# lines of this run only: from its START line (the token) on
run_lines() {
	awk -v t="SFPROBE START token=$TOKEN" 'index($0, t) { on = 1 } on' "$LOG" 2>/dev/null || true
}
status=timeout
waited=0
while [ "$waited" -lt "$TIMEOUT" ]; do
	sleep 5
	waited=$((waited + 5))
	lines="$(run_lines)"
	if grep -q 'SFPROBE DONE' <<<"$lines"; then
		status=done
		break
	fi
	if grep -q 'SFPROBE ERROR' <<<"$lines"; then
		status=error
		break
	fi
	if [ "$waited" -ge 60 ] && [ -z "$(prefix_pids)" ]; then
		status=died # Noita exited or never started
		break
	fi
done
sleep 2
run_lines | grep 'SFPROBE' >"$OUT" || true
cp "$LOG" "$OUT_LOG" 2>/dev/null || true
pids="$(prefix_pids)"
if [ -n "$pids" ]; then
	kill $pids 2>/dev/null || true
	sleep 3
	pids="$(prefix_pids)"
	if [ -n "$pids" ]; then
		kill -9 $pids 2>/dev/null || true
	fi
fi
# finishing is not passing: an ABORT or a failed check makes the run fail too
if [ "$status" = done ] && { grep -q 'SFPROBE ABORT' "$OUT" || ! grep -qE 'SFPROBE SUMMARY [0-9]+ passed, 0 failed' "$OUT"; }; then
	status=failed
fi
echo "probe $status: $(wc -l <"$OUT") lines in $OUT"
grep -E 'FAIL|ERROR|SUMMARY|ABORT' "$OUT" || true
[ "$status" = done ]

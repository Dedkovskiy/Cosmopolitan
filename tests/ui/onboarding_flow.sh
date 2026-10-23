#!/bin/zsh
# Item 40, the whole flow in a throwaway home (HOME and CFFIXED_USER_HOME): a fresh Mac (no engine, nothing accepted) gets the onboarding,
# with only the screens this Mac needs; quitting midway resumes at the same screen; the engine is prepared in the background (from local
# copies of the pinned Sikarugir files, hash-checked like a download); at the end the terms are accepted, setup is ready and the Library
# opens. Your real install is only compared before and after.
source "${0:A:h}/../lib/testenv.sh"
fail() { print "FAIL: $*"; exit 1; }
tw_snapshot
TESTENV_NO_ENGINE=1 testenv_init >/dev/null || exit 1; app=""; trap '[[ -n "$app" ]] && kill $app 2>/dev/null; testenv_cleanup' EXIT   # the app too, if a step fails
SK="$TH/Library/Application Support/Sikarugir"; mkdir -p "$SK/Engines" "$SK/Template"
cp -c "$REAL_HOME/Library/Application Support/Sikarugir/Engines/$ENGINE.tar.xz" "$SK/Engines/" && cp -cR "$REAL_HOME/Library/Application Support/Sikarugir/Template/Template-1.0.24.app" "$SK/Template/" || fail "no local Sikarugir copies to set up from"
L="$TH/Library/Logs/Cosmopolitan.log"
gui() { sandbox-exec -p "$(tw_sandbox_profile)" env CFFIXED_USER_HOME="$TH" HOME="$TH" COSMO_TEST_HOME="$TH" COSMO_TEST_ONBOARDING_AUTOPLAY=1 "$@" "$T/CosmopolitanTest.app/Contents/MacOS/Cosmopolitan" >/dev/null 2>&1 & app=$!; }
seen() { grep -q "$1" "$L" 2>/dev/null; }
gui COSMO_TEST_ONBOARDING_STOP=4
poll 60 seen "onboarding: at Your games" || fail "the flow never reached Your games: $(grep onboarding: "$L")"
kill $app; wait $app 2>/dev/null; cp "$L" "$T/first-run.log"
print "  saved screen after quitting: $(CFFIXED_USER_HOME="$TH" defaults read "$TESTID" onboardingStep 2>&1)"; grep onboarding: "$L" | sed 's/^/  first run: /'
print -r -- "ok: $(grep -m1 'onboarding: started' "$L" | sed 's/^onboarding: //')"
print -r -- "ok: then $(grep 'onboarding: at' "$L" | sed 's/^onboarding: //' | tr '\n' ' ')— and the app was quit there"
gui
poll 30 seen "onboarding: resumed at Your games" || fail "no resume at Your games: $(grep onboarding: "$L" | tail -3)"
print "ok: relaunched, it resumed at Your games"
poll 600 seen "onboarding: finished" || fail "the flow never finished: $(tail -5 "$L")"
kill $app; wait $app 2>/dev/null
grep -q "onboarding: finished; setup ready" "$L" || fail "setup did not finish: $(grep 'onboarding: finished' "$L")"
[[ -f "$TS/terms-accepted.json" ]] || fail "terms not accepted after the flow (support folder: $(ls -A "$TS" | tr '\n' ' '))"
[[ -e "$TS/engines/$ENGINE/wswine.bundle/bin/wine" ]] || fail "engine missing after the flow (engines: $(ls -A "$TS/engines" 2>/dev/null | tr '\n' ' '); $(grep 'onboarding: finished' "$L"))"
done=$(CFFIXED_USER_HOME="$TH" defaults read "$TESTID" onboardingDone 2>/dev/null)
[[ "$done" == 1 ]] || fail "onboarding not marked done ($done)"
print "ok: finished in the throwaway home: terms accepted, engine set up in the background, onboarding marked done"
tw_check || fail "your real data changed"
print "PASS onboarding_flow"

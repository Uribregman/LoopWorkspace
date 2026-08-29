#!/bin/sh
#
#  check-read-only.sh
#  LoopFollow
#
#  ⛔ THE BOUNDARY, ENFORCED BY THE BUILD RATHER THAN BY GOOD INTENTIONS.
#
#  Two properties this app must never lose:
#    1. It links NOTHING from the pump side. It cannot dose, cannot talk to a
#       pump, and cannot be made to by accident, because the dependency is not
#       there to misuse.
#    2. It contains NO CloudKit write. Data flows Loop → follower and nothing
#       comes back. A follower able to send anything to the patient's phone is
#       an attack surface on an insulin pump.
#
#  Both are easy to add without noticing and impossible to spot in review once
#  the app is more than a few files. So the build refuses instead.
#
#  ⚠️ IF THIS FIRES, THE FIX IS NOT TO RELAX THE PATTERN. It is to not do the
#  thing. The one legitimate edit here is adding a pattern, never removing one.
#
#  ⚠️ COMMENTS ARE STRIPPED BEFORE SCANNING. The first version of this check
#  failed the build on its own documentation — the banners in this app discuss
#  PumpManager and CGMManager precisely to say it must not touch them. A guard
#  that cannot tell prose from code trains people to disable it, which is worse
#  than not having it.
#

set -eu

SRC="${SRCROOT}/LoopFollow"
FOUND=0

# Print every line of Swift source that is not a comment, as file:line:text.
code_lines() {
    find "$SRC" -name '*.swift' -print0 \
        | xargs -0 grep -n '' \
        | awk '{
            body = $0
            sub(/^[^:]*:[0-9]+:/, "", body)
            sub(/^[ \t]+/, "", body)
            if (body ~ /^\/\//) next        # line comment
            if (body ~ /^\*/) next          # continuation of a block comment
            if (body ~ /^\/\*/) next        # block comment opener
            print
        }'
}

scan() {
    pattern="$1"
    message="$2"
    hits=$(code_lines | grep -E "$pattern" || true)
    if [ -n "$hits" ]; then
        echo "$hits"
        echo "error: $message"
        FOUND=1
    fi
}

scan '^[[:space:]]*import[[:space:]]+(LoopKit|LoopKitUI|LoopCore|LoopAlgorithm|MinimedKit|OmniKit|OmnipodKit|CGMBLEKit|G7SensorKit|RileyLinkKit|LibreTransmitter)' \
     "LoopFollow imported a module from the pump side. This app is a viewer; it must not link anything that can dose. See the banner in LoopFollowApp.swift."

scan '(PumpManager|CGMManager|LoopDataManager|DeviceDataManager|DoseEnactor|enactBolus|enactTempBasal)' \
     "LoopFollow referenced a device or dosing type. It is a viewer."

scan '(CKModifyRecordsOperation|privateCloudDatabase|\.modifyRecords|database\.save\(|CKRecord\(recordType)' \
     "LoopFollow contains a CloudKit write, or reaches for the private database instead of the shared one. Data flows Loop -> follower and nothing comes back."

if [ "$FOUND" -ne 0 ]; then
    exit 1
fi

echo "LoopFollow read-only boundary: clean."

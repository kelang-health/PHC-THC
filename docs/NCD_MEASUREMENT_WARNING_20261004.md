# Cloud measurement warning 2.0.142

Warnings appear in the form before saving and require confirmation on Save. Cancel returns to measurements without calling the save RPC.

Review windows (data checks, not clinical normal ranges): height 130–200 cm, weight 30–150 kg, waist 50–150 cm, BMI 16–40, pulse 50–120/min. Height 220 always warns, even if history is also 220.

History comparison: height difference >5 cm; weight difference >10 kg OR >20%; waist >10 cm; effective systolic >30 mmHg; effective diastolic >20 mmHg. Missing history is not treated as zero. Historical differences are prompts to verify, not diagnoses, because visits may be separated by a long time.

Existing BP repeat requirement and clinical warnings remain. Fasting glucose 100–125 also prompts follow-up; abnormal results remain recordable after confirmation.

Scope: browser form warnings. Existing server hard bounds remain unchanged. This release does not add server-side per-value confirmation or alter historical data/JHCIS visits.

Validation: tools/test_ncd_measurement_warning.cjs covers normal, height 220 with identical history, history deltas, missing history, optional pulse, fasting glucose, cancel and confirm. Browser verification checks real confirmation dialog and live warning text.

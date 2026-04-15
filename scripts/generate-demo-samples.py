#!/usr/bin/env python3
"""
Generate Swift literal arrays for demo usage graph data.
Outputs Swift code to stdout.

Usage: python3 scripts/generate-demo-samples.py
"""

import random

random.seed(42)


def generate_samples(
    window_duration: int,
    time_remaining: int,
    target_utilization: int,
    n_samples: int,
    gap: tuple[int, int] | None = None,
) -> list[tuple[int, int]]:
    """
    Generate (offset_from_reset, utilization) samples.

    Args:
        window_duration: Total window length in seconds (e.g. 18000 for 5h)
        time_remaining: Seconds until resetsAt from "now"
        target_utilization: Final utilization percentage (0-100)
        n_samples: Approximate number of samples to generate
        gap: Optional (gap_start_offset, gap_end_offset) as seconds from window start.
             Samples in this range are skipped (simulates user away).
    """
    # "now" offset relative to resetsAt
    now_offset = -time_remaining
    # window start offset relative to resetsAt
    window_start_offset = -window_duration

    # Time span covered by samples: window_start_offset -> now_offset
    time_span = now_offset - window_start_offset  # positive number of seconds

    # Build sample time offsets (seconds from resetsAt)
    if gap is None:
        # Evenly spread across the whole span
        raw_offsets = [
            window_start_offset + int(i * time_span / (n_samples - 1))
            for i in range(n_samples)
        ]
    else:
        # gap is (gap_start_secs_from_start, gap_end_secs_from_start) in window-relative seconds
        gap_start_abs = window_start_offset + gap[0]
        gap_end_abs = window_start_offset + gap[1]

        before_span = gap_start_abs - window_start_offset
        after_span = now_offset - gap_end_abs

        # Split samples roughly proportional to time span on each side
        n_before = max(3, int(n_samples * before_span / (before_span + after_span)))
        n_after = max(3, n_samples - n_before)

        before_offsets = [
            window_start_offset + int(i * before_span / (n_before - 1))
            for i in range(n_before)
        ]
        after_offsets = [
            gap_end_abs + int(i * after_span / (n_after - 1))
            for i in range(n_after)
        ]
        raw_offsets = before_offsets + after_offsets

    # Deduplicate and sort
    raw_offsets = sorted(set(raw_offsets))

    n = len(raw_offsets)
    # Assign utilization values: monotonically increasing with small noise,
    # clamped to 0..100, forced to target at final sample.
    utilizations = []
    running_max = 0
    for i, offset in enumerate(raw_offsets):
        if i == n - 1:
            # Final sample must be exactly target
            utilizations.append(target_utilization)
            continue

        # Fraction through sample sequence (0.0 at start, approaches 1.0 at end)
        frac = i / (n - 1)
        base = target_utilization * frac
        noise = random.uniform(-2, 2)
        value = int(base + noise)
        value = max(running_max, max(0, min(100, value)))
        running_max = value
        utilizations.append(value)

    # Enforce monotonicity in a second pass (forward)
    for i in range(1, len(utilizations) - 1):
        if utilizations[i] < utilizations[i - 1]:
            utilizations[i] = utilizations[i - 1]

    # Ensure the target at the end doesn't break monotonicity:
    # clamp all preceding values to <= target
    for i in range(len(utilizations) - 1):
        if utilizations[i] > target_utilization:
            utilizations[i] = target_utilization

    return list(zip(raw_offsets, utilizations))


def format_array(name: str, comment: str, samples: list[tuple[int, int]]) -> str:
    lines = [f"// {comment}"]
    lines.append(f"private static let {name}: [(TimeInterval, Int)] = [")
    # Format in rows of up to 6 tuples per line for readability
    chunk_size = 6
    chunks = [samples[i:i + chunk_size] for i in range(0, len(samples), chunk_size)]
    for chunk in chunks:
        row = ", ".join(f"({t}, {u})" for t, u in chunk)
        lines.append(f"    {row},")
    # Remove trailing comma from last line for cleanliness (Swift allows it but avoid it)
    if lines[-1].endswith(","):
        lines[-1] = lines[-1][:-1]
    lines.append("]")
    return "\n".join(lines)


def main() -> None:
    # -----------------------------------------------------------------------
    # Scenario 1: Slow consumption
    # 5h window, resetsAt 2.7h from now, utilization 42%
    s1_5h = generate_samples(
        window_duration=18000,
        time_remaining=int(2.7 * 3600),
        target_utilization=42,
        n_samples=25,
    )

    # 7d window, resetsAt 4.5 days from now, utilization 18%
    s1_7d = generate_samples(
        window_duration=604800,
        time_remaining=int(4.5 * 86400),
        target_utilization=18,
        n_samples=20,
    )

    # -----------------------------------------------------------------------
    # Scenario 2: Fast consumption with a gap
    # 5h window, resetsAt 1.4h from now, utilization 74%
    # Gap: 40 min starting ~1.5h into the window
    s2_5h = generate_samples(
        window_duration=18000,
        time_remaining=int(1.4 * 3600),
        target_utilization=74,
        n_samples=30,
        gap=(int(1.5 * 3600), int(1.5 * 3600) + 40 * 60),  # 40-minute gap
    )

    # 7d window, resetsAt 4.2 days from now, utilization 61%
    s2_7d = generate_samples(
        window_duration=604800,
        time_remaining=int(4.2 * 86400),
        target_utilization=61,
        n_samples=25,
    )

    # -----------------------------------------------------------------------
    # Scenario 4: Exhausted
    # 5h window, resetsAt 2.25h from now, utilization 100%
    # Hit 100% about 30 minutes ago → plateau samples at end
    # Generate samples only up to 30 min before now (the "hit 100" point),
    # then append evenly-spaced plateau samples from there to "now".
    now_offset_s4 = -int(2.25 * 3600)
    hit_100_offset = now_offset_s4 - 30 * 60  # 30 min before now
    s4_5h_base = generate_samples(
        window_duration=18000,
        time_remaining=int(2.25 * 3600) + 30 * 60,  # pretend "now" is 30 min earlier
        target_utilization=100,
        n_samples=23,
    )
    # Append 6 plateau samples from hit_100_offset to now_offset_s4
    n_plateau = 7
    plateau_samples = [
        (hit_100_offset + int(i * 30 * 60 / (n_plateau - 1)), 100)
        for i in range(n_plateau)
    ]
    s4_5h = s4_5h_base + plateau_samples[1:]  # skip first plateau point (== last base point)

    # 7d window, resetsAt 3.5 days from now, utilization 38%
    s4_7d = generate_samples(
        window_duration=604800,
        time_remaining=int(3.5 * 86400),
        target_utilization=38,
        n_samples=25,
    )

    # 7d Sonnet window, resetsAt 3.5 days from now, utilization 22%
    s4_7d_sonnet = generate_samples(
        window_duration=604800,
        time_remaining=int(3.5 * 86400),
        target_utilization=22,
        n_samples=20,
    )

    # -----------------------------------------------------------------------
    # Scenario 3: Very high consumption
    # 5h window, resetsAt 0.8h from now, utilization 91%
    s3_5h = generate_samples(
        window_duration=18000,
        time_remaining=int(0.8 * 3600),
        target_utilization=91,
        n_samples=25,
    )

    # 7d window, resetsAt 1.5 days from now, utilization 85%
    s3_7d = generate_samples(
        window_duration=604800,
        time_remaining=int(1.5 * 86400),
        target_utilization=85,
        n_samples=25,
    )

    # -----------------------------------------------------------------------
    # Output
    print("// MARK: - Demo Samples (generated by scripts/generate-demo-samples.py)")
    print()

    print(format_array(
        "samples_s1_5h",
        "Scenario 1: Slow consumption (5h window, 42%)",
        s1_5h,
    ))
    print()

    print(format_array(
        "samples_s1_7d",
        "Scenario 1: Slow 7d window (18%)",
        s1_7d,
    ))
    print()

    print(format_array(
        "samples_s2_5h",
        "Scenario 2: Fast consumption with gap (5h window, 74%)",
        s2_5h,
    ))
    print()

    print(format_array(
        "samples_s2_7d",
        "Scenario 2: Moderate 7d window (61%)",
        s2_7d,
    ))
    print()

    print(format_array(
        "samples_s4_5h",
        "Scenario 4: Exhausted — hit 100% ~30min ago (5h window, 100%)",
        s4_5h,
    ))
    print()

    print(format_array(
        "samples_s4_7d",
        "Scenario 4: Gentle 7d window (38%)",
        s4_7d,
    ))
    print()

    print(format_array(
        "samples_s4_7d_sonnet",
        "Scenario 4: Very gentle 7d Sonnet window (22%)",
        s4_7d_sonnet,
    ))
    print()

    print(format_array(
        "samples_s3_5h",
        "Scenario 3: Very high consumption (5h window, 91%)",
        s3_5h,
    ))
    print()

    print(format_array(
        "samples_s3_7d",
        "Scenario 3: High 7d window (85%)",
        s3_7d,
    ))


if __name__ == "__main__":
    main()

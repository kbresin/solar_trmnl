def to_energy_unit(wh) -> tuple[float, str]:
    """Convert watt-hours to the most readable energy unit."""
    value = float(wh)

    thresholds = [
        (1e12, "TWh"),
        (1e9,  "GWh"),
        (1e6,  "MWh"),
        (1e3,  "kWh"),
    ]

    for divisor, unit in thresholds:
        if abs(value) >= divisor:
            return value / divisor, unit

    return value, "Wh"


def format_energy(wh, precision: int = 2) -> str:
    value, unit = to_energy_unit(wh)
    return f"{value:.{precision}f} {unit}"


if __name__ == "__main__":
    import sys

    if len(sys.argv) != 2:
        print("Usage: energy_units.py <wh>")
        sys.exit(1)

    print(format_energy(sys.argv[1]))

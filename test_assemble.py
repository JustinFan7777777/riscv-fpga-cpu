from pathlib import Path
from tempfile import TemporaryDirectory

from assemble import assemble


def test_li_expansion_and_labels():
    with TemporaryDirectory() as d:
        asm = Path(d) / "li_test.asm"
        asm.write_text(
            """
_start:
    li s3, 0x800
    j done
    li t0, 1
done:
    li t6, 0xFFFF
    li t0, -1
""",
            encoding="utf-8",
        )
        resolved, labels = assemble(str(asm))

    assert labels["done"] == 16
    assert resolved[0] == 0x000019B7
    assert resolved[4] == 0x80098993
    assert resolved[16] == 0x00010FB7
    assert resolved[20] == 0xFFFF8F93
    assert resolved[24] == 0xFFF00293


if __name__ == "__main__":
    test_li_expansion_and_labels()
    print("assemble.py self-check PASS")

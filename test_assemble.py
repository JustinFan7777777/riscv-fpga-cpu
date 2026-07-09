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


def test_byte_and_half_load_store_encodings():
    with TemporaryDirectory() as d:
        asm = Path(d) / "mem_width_test.asm"
        asm.write_text(
            """
    lb  t1, 1(x0)
    lh  t2, 2(x0)
    lbu t3, 3(x0)
    lhu t4, 4(x0)
    sb  t1, 5(x0)
    sh  t2, 6(x0)
""",
            encoding="utf-8",
        )
        resolved, _ = assemble(str(asm))

    assert resolved[0] == 0x00100303
    assert resolved[4] == 0x00201383
    assert resolved[8] == 0x00304E03
    assert resolved[12] == 0x00405E83
    assert resolved[16] == 0x006002A3
    assert resolved[20] == 0x00701323


def test_mul_encoding():
    with TemporaryDirectory() as d:
        asm = Path(d) / "mul_test.asm"
        asm.write_text("mul t0, t1, t2\n", encoding="utf-8")
        resolved, _ = assemble(str(asm))

    assert resolved[0] == 0x027302B3


if __name__ == "__main__":
    test_li_expansion_and_labels()
    test_byte_and_half_load_store_encodings()
    test_mul_encoding()
    print("assemble.py self-check PASS")

"""Run from the repository root; only writes temporary fixtures outside the tree."""
import pathlib
import shutil
import subprocess
import tempfile

repo = pathlib.Path.cwd()
with tempfile.TemporaryDirectory(prefix="let-no-collector-") as tmp:
    root = pathlib.Path(tmp)
    (root / "tools").mkdir()
    for name in ["validate_no_collector.lua", "tool_util.lua"]:
        shutil.copyfile(repo / "tools" / name, root / "tools" / name)

    def check(name, valid):
        result = subprocess.run(
            ["/tmp/lua-compat", "tools/validate_no_collector.lua"],
            cwd=root, text=True, capture_output=True,
        )
        print(name, "exit=" + str(result.returncode))
        print(result.stdout + result.stderr, end="")
        assert (result.returncode == 0) == valid

    check("empty active fixture", True)
    (root / "vendor/whippet").mkdir(parents=True)
    check("empty collector directory", False)
    (root / "vendor/whippet").rmdir()
    (root / "src").mkdir()
    source = root / "src/owner.c"
    source.write_text("void run(void) { gc_collect(thread); }\n")
    check("collector API", False)
    source.unlink()
    (root / "Makefile").write_text("LDLIBS += -lgc\n")
    check("collector link dependency", False)
    (root / "Makefile").unlink()
    (root / "research/archive/old").mkdir(parents=True)
    archived = root / "research/archive/old/owner.c"
    archived.write_text("void run(void) { gc_collect(thread); }\n")
    check("preserved archive is excluded", True)
    source.write_text('#include "../research/archive/old/owner.c"\n')
    check("archive imported into active source", False)
    source.unlink()
    archived.write_text("void run(void) {}\n")
    source.symlink_to("../research/archive/old/owner.c")
    check("archive symlink into active source", False)
    source.unlink()
    source.write_text("/* ordinary conservative effect barrier */\neffect.safepoint = true;\n")
    check("generic call synchronization preserved", True)
print("PASS: 8 filesystem-level dependency guard controls")

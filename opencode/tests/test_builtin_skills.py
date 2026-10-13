"""Bundled skill discovery must preserve existing mounted user definitions."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "link-builtin-skills.sh"


class BuiltinSkillTests(unittest.TestCase):
    def test_ephemeral_links_preserve_user_skills_and_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / "home"
            config = root / "config"
            builtin = root / "builtin"
            for name in ("new", "shared", "opencode", "claude"):
                path = builtin / name
                path.mkdir(parents=True)
                (path / "SKILL.md").write_text("bundled")
                (path / "reference.md").write_text("resource")
            for path in (home / ".agents/skills/shared", config / "opencode/skills/opencode",
                         home / ".claude/skills/claude"):
                path.mkdir(parents=True)
                (path / "SKILL.md").write_text("user")
            environment = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config))
            for _ in range(2):
                subprocess.run(["bash", str(SCRIPT), str(builtin)], env=environment, check=True)
            added = home / ".claude/skills/new"
            self.assertTrue(added.is_symlink())
            self.assertEqual((added / "reference.md").read_text(), "resource")
            self.assertFalse((home / ".claude/skills/shared").exists())
            self.assertFalse((home / ".claude/skills/opencode").exists())
            self.assertEqual((home / ".claude/skills/claude/SKILL.md").read_text(), "user")
            self.assertEqual((home / ".agents/skills/shared/SKILL.md").read_text(), "user")
            self.assertEqual((config / "opencode/skills/opencode/SKILL.md").read_text(), "user")

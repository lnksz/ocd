"""Exercise shared agent mounts without launching containers or using host config."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class SharedAgentsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="pid test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("PID_", "XDG_"))}
        self.env.update(HOME=str(self.home), PID_ENGINE="capture",
                        PID_CPUS="2", PID_MEMORY="1g")

    def launch(self):
        script = '''
function capture
    printf '%s\\0' $argv
end
source "$argv[1]"
pid --shell
'''
        result = subprocess.run(["fish", "--no-config", "-c", script,
                                 str(ROOT / "pi/pid.fish")], env=self.env,
                                cwd=self.root, capture_output=True, check=True)
        return result.stdout.decode().split("\0")[:-1]

    def test_missing_shared_folder_is_not_created_or_mounted(self):
        args = self.launch()
        self.assertFalse((self.home / ".agents").exists())
        self.assertFalse(any(":/tmp/home/.agents:" in arg for arg in args))

    def test_shared_folder_without_skills_is_mounted_read_only(self):
        shared = self.home / ".agents"
        shared.mkdir()
        (shared / "config.json").write_text("{}")
        self.assertIn(f"{shared}:/tmp/home/.agents:ro", self.launch())
        self.assertFalse((shared / "skills").exists())

    def test_symlinked_skills_keep_narrow_read_only_targets(self):
        shared = self.home / ".agents"
        shared.mkdir()
        skills = self.root / "external skills"
        skills.mkdir()
        other = self.root / "external skill"
        other.mkdir()
        (other / "SKILL.md").write_text("shared skill")
        (shared / "skills").symlink_to(skills, target_is_directory=True)
        (skills / "other").symlink_to(other, target_is_directory=True)
        (skills / "duplicate").symlink_to(other, target_is_directory=True)
        args = self.launch()
        for mount in (f"{shared}:/tmp/home/.agents:ro", f"{skills}:{skills}:ro",
                      f"{other}:{other}:ro"):
            self.assertIn(mount, args)
            self.assertEqual(args.count(mount), 1)
        self.assertNotIn(f"{self.home}:{self.home}", args)


if __name__ == "__main__":
    unittest.main()

"""Exercise version gates without launching containers or touching user data."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WRAPPER = Path(os.environ.get('OCD_TEST_WRAPPER', ROOT / 'opencode/ocd.fish'))
ENGINE = '''#!/usr/bin/env python3
import os,sys,json
with open(os.environ['CALLS'],'a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
if '--entrypoint' in sys.argv:
 print(os.environ['GUEST_VERSION'])
 sys.exit(int(os.environ.get('PROBE_STATUS','0')))
sys.exit(int(os.environ.get('RUN_STATUS','0')))
'''

class GateTestCase(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ocd test ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        engine = self.bin / 'engine'
        engine.write_text(ENGINE)
        engine.chmod(0o755)
        binary = self.bin / 'opencode'
        binary.write_text('#!/bin/sh\nif [ "${PROBE_INITIALIZES_XDG:-0}" = 1 ]; then mkdir -p "$XDG_DATA_HOME/opencode" "$XDG_STATE_HOME/opencode"; fi\nprintf "%s\\n" "$HOST_VERSION"\nexit "${HOST_STATUS:-0}"\n')
        binary.chmod(0o755)
        self.env = {k:v for k,v in os.environ.items() if not k.startswith(('OCD_','OPENCODE_','XDG_','HOST_'))}
        self.env.update(HOME=str(self.home), XDG_CONFIG_HOME=str(self.home/'config'),
                        XDG_CACHE_HOME=str(self.home/'cache'), XDG_DATA_HOME=str(self.home/'data'),
                        OCD_ENGINE=str(engine), OCD_CPUS='2', OCD_MEMORY='1g',
                        PATH=f'{self.bin}:'+os.environ['PATH'], CALLS=str(self.root/'calls'),
                        HOST_VERSION='opencode v2.0.22', GUEST_VERSION='opencode v2.0.22')

    def launch(self,*args,code=0):
        result=subprocess.run(['fish','--no-config','-c','source "$argv[1]"; ocd $argv[2..-1]',str(WRAPPER),*args],
                              env=self.env,cwd=self.root,capture_output=True,text=True)
        self.assertEqual(result.returncode,code,result.stderr)
        calls=[json.loads(line) for line in (self.root/'calls').read_text().splitlines()]
        self.assertEqual(calls[0],['run','--rm','--entrypoint','opencode','docker.io/lnksz/ocd:latest','--version'])
        return result,calls

class VersionGateTests(GateTestCase):
    def test_same_series_patch_and_version_prefixes(self):
        for host,guest in [('2.0.22','2.0.23'),('opencode v2.0.22','v2.0.1'),('2.0.22+local','2.0.23-beta.1')]:
            with self.subTest(host=host,guest=guest):
                (self.root/'calls').unlink(missing_ok=True)
                self.env.update(HOST_VERSION=host,GUEST_VERSION=guest)
                _,calls=self.launch('--model','a model','prompt with spaces')
                self.assertEqual(len(calls),2)
                run=calls[1]
                self.assertIn(f'HOST_OPENCODE_VERSION={host}',run)
                self.assertIn('OCD_FORCE_VERSION_MISMATCH=0',run)
                self.assertIn('XDG_STATE_HOME=/tmp/home/.local/state',run)
                self.assertIn('OPENCODE_CLI_CONFIG_CONTENT={"keybinds":{"terminal.suspend":"none"}}',run)
                self.assertEqual(run[-3:],['--model','a model','prompt with spaces'])
                self.assertIn('opencode --standalone --auto "$@"',run[run.index('-c')+1])

    def test_rejects_mismatch_and_unknown_before_creating_data(self):
        for version in ['1.18.34','2.1.0','','garbage','2.0.22\n2.0.23']:
            with self.subTest(version=version):
                (self.root/'calls').unlink(missing_ok=True)
                self.env['GUEST_VERSION']=version
                result,calls=self.launch('--shell',code=1)
                self.assertEqual(len(calls),1)
                self.assertFalse((self.home/'data/opencode').exists())
                self.assertFalse((self.home/'config/opencode').exists())
                self.assertIn('--force-version-mismatch',result.stderr)

    def test_failed_probes_are_rejected(self):
        for variable in ['PROBE_STATUS','HOST_STATUS']:
            with self.subTest(variable=variable):
                (self.root/'calls').unlink(missing_ok=True)
                self.env[variable]='9'
                _,calls=self.launch(code=1)
                self.assertEqual(len(calls),1)
                self.env.pop(variable)

    def test_force_override_and_shell_arguments(self):
        self.env['GUEST_VERSION']='1.18.34'
        result,calls=self.launch('--force-version-mismatch','--shell','-c','echo hello')
        self.assertIn('forcing',result.stderr)
        self.assertEqual(calls[1][-3:],['fish','-c','echo hello'])
        self.assertIn('OCD_FORCE_VERSION_MISMATCH=1',calls[1])
        self.assertNotIn('--force-version-mismatch',calls[1])
        self.assertFalse(any('OPENCODE_CLI_CONFIG_CONTENT' in arg for arg in calls[1]))

    def test_run_exit_status_is_preserved(self):
        self.env['RUN_STATUS']='23'
        self.launch(code=23)

    def test_argument_separator_does_not_consume_guest_flag(self):
        _,calls=self.launch('--','--force-version-mismatch')
        self.assertEqual(calls[1][-1],'--force-version-mismatch')
        self.assertIn('OCD_FORCE_VERSION_MISMATCH=0',calls[1])

class EntrypointGateTests(GateTestCase):
    def launch_entrypoint(self,host,guest,force=False,code=0):
        self.env.update(HOST_OPENCODE_VERSION=host, HOST_VERSION=guest,
                        OCD_FORCE_VERSION_MISMATCH=str(int(force)),
                        XDG_CONFIG_HOME=str(self.home/'config'),
                        XDG_CACHE_HOME=str(self.home/'cache'), XDG_DATA_HOME=str(self.home/'data'))
        result=subprocess.run(['bash',str(ROOT/'opencode/entrypoint.sh'),'true'],
                              env=self.env,cwd=self.root,capture_output=True,text=True)
        self.assertEqual(result.returncode,code,result.stderr)
        return result

    def test_entrypoint_blocks_before_mounted_path_writes(self):
        self.env["PROBE_INITIALIZES_XDG"]="1"
        self.launch_entrypoint('2.0.22','2.1.0',code=1)
        self.assertFalse((self.home/'data/opencode').exists())
        self.assertFalse((self.home/'config/opencode').exists())

    def test_entrypoint_accepts_patch_and_override(self):
        self.launch_entrypoint('opencode v2.0.22','v2.0.23')
        result=self.launch_entrypoint('2.0.22','1.18.34',force=True)
        self.assertIn('forcing',result.stderr)
        self.assertFalse((self.home/'config/opencode/plugins/rtk.ts').exists())

if __name__=='__main__':unittest.main()

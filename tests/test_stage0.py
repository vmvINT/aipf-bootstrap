import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LINUX = ROOT / 'linux'

class LinuxStage0(unittest.TestCase):
    def test_shell_syntax(self):
        for script in (LINUX / 'aipf-setup.sh', LINUX / 'aipf'):
            p = subprocess.run(['sh', '-n', str(script)], capture_output=True, text=True)
            self.assertEqual(p.returncode, 0, p.stderr)

    def test_launcher_commands(self):
        p = subprocess.run(['sh', str(LINUX/'aipf'), 'version'], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0)
        self.assertIn('0.1.0', p.stdout)
        for args, code, message in [(['boot','twin'],4,'BLOCKED_STAGE2'),(['update','twin'],4,'BLOCKED_STAGE2'),(['rollback','twin'],4,'BLOCKED_STAGE2'),(['boot','bad/name'],2,'INVALID_PROFILE'),(['boom'],2,'UNKNOWN_COMMAND')]:
            p = subprocess.run(['sh', str(LINUX/'aipf'), *args], capture_output=True, text=True)
            self.assertEqual(p.returncode, code)
            self.assertIn(message, p.stderr)

    def test_plan_is_read_only_and_apply_installs_launcher(self):
        with tempfile.TemporaryDirectory() as d:
            home=Path(d)
            mockdir=home/'mocks'
            mockdir.mkdir()
            gh=mockdir/'gh'
            gh.write_text('#!/bin/sh\nexit 0\n')
            gh.chmod(0o755)
            bindir=home/'bin'
            env={**os.environ,'HOME':str(home),'AIPF_BIN_DIR':str(bindir),'PATH':str(mockdir)+':'+os.environ['PATH']}
            plan=subprocess.run(['sh',str(LINUX/'aipf-setup.sh'),'--plan'],capture_output=True,text=True,env=env)
            self.assertEqual(plan.returncode,0,plan.stderr)
            self.assertFalse(bindir.exists())
            apply=subprocess.run(['sh',str(LINUX/'aipf-setup.sh'),'--apply'],capture_output=True,text=True,env=env)
            self.assertEqual(apply.returncode,0,apply.stderr)
            self.assertTrue((bindir/'aipf').is_file())
            doctor=subprocess.run([str(bindir/'aipf'),'doctor'],capture_output=True,text=True,env=env)
            self.assertEqual(doctor.returncode,0,doctor.stderr)
            self.assertIn('STATUS=STAGE1_READY_STAGE2_PENDING',doctor.stdout)
            again=subprocess.run(['sh',str(LINUX/'aipf-setup.sh'),'--apply'],capture_output=True,text=True,env=env)
            self.assertEqual(again.returncode,0,again.stderr)

    def test_no_private_identifiers(self):
        for path in list(LINUX.glob('*'))+list((ROOT/'windows').glob('*')):
            content=path.read_text().lower()
            for token in ('vmvint/sre_twin','vmvint/aipf','ghp_','github_pat_','inc0000'):
                self.assertNotIn(token,content,path.name)

if __name__ == '__main__':
    unittest.main()

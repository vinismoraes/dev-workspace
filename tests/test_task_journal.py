import os
from datetime import date
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(os.environ.get('JOURNAL_REPO', Path(__file__).resolve().parents[1]))
SCRIPT = ROOT / 'task-journal.py'
DAY = '2026-10-29'


class TaskJournalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.vault = Path(self.tmp.name) / 'vault'

    def run_journal(self, action, branch='PP-97', *extra, success=True):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), action, branch, '--vault', str(self.vault),
             '--date', DAY, *extra], capture_output=True, text=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def note(self, name='PP-97 PDF improvements.md', content=None):
        p = self.vault / 'projects' / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content or '# PP-97 PDF improvements\n#pdf\n\n**Status**: IN PROGRESS\n**Branch**: PP-97\n\n## Context\nExisting context.\n\n## Decisions\n- Keep this decision.\n')
        return p

    def test_start_creates_project_and_preserves_it_on_repeat(self):
        self.run_journal('start', 'feature/PP-97-parser', '--title', 'PDF improvements', '--repo', 'aorta')
        p = self.vault / 'projects' / 'PP-97 PDF improvements.md'
        self.assertIn('**Status**: IN PROGRESS', p.read_text())
        self.assertIn('**Repos**: aorta', p.read_text())
        p.write_text(p.read_text() + '\n## Personal notes\nKeep me.\n')
        before = p.read_text()
        self.run_journal('start', 'feature/PP-97-parser')
        self.assertEqual(before, p.read_text())
        self.run_journal('verify', 'feature/PP-97-parser')

    def test_finish_without_start_creates_notes_and_verifies(self):
        self.run_journal('finish', 'PP-97', '--title', 'PDF improvements', '--summary', 'Finished the investigation.')
        self.run_journal('verify', 'PP-97', '--completed')
        self.assertIn('**Status**: DONE', (self.vault / 'projects' / 'PP-97 PDF improvements.md').read_text())
        daily = (self.vault / 'daily' / f'{DAY}.md').read_text()
        self.assertIn('[[PP-97 PDF improvements]]', daily)
        self.assertIn('Finished the investigation.', daily)

    def test_finish_preserves_existing_notes_and_is_idempotent(self):
        p = self.note()
        d = self.vault / 'daily' / f'{DAY}.md'
        d.parent.mkdir()
        d.write_text('# Today\n\n## Activity\n- Earlier work.\n\n## Notes\n- Keep this too.\n')
        self.run_journal('finish')
        before = (p.read_text(), d.read_text())
        self.run_journal('finish')
        self.assertEqual(before, (p.read_text(), d.read_text()))
        self.assertIn('Existing context.', p.read_text())
        self.assertIn('- Keep this decision.', p.read_text())
        self.assertIn('- Earlier work.', d.read_text())
        self.assertIn('## Notes\n- Keep this too.', d.read_text())
        self.assertEqual(d.read_text().count('[[PP-97 PDF improvements]]'), 1)

    def test_ticket_matching_does_not_match_longer_ticket(self):
        other = self.note('PP-970 Other.md')
        before = other.read_text()
        self.run_journal('finish', 'feature/PP-97-parser')
        self.assertEqual(other.read_text(), before)
        self.assertTrue((self.vault / 'projects' / 'PP-97.md').exists())

    def test_ambiguous_notes_fail_without_modification(self):
        a = self.note()
        b = self.note('PP-97 Other.md')
        before = (a.read_text(), b.read_text())
        self.run_journal('finish', success=False)
        self.assertEqual(before, (a.read_text(), b.read_text()))
        self.assertFalse((self.vault / 'daily' / f'{DAY}.md').exists())

    def test_malformed_daily_note_fails_before_marking_done(self):
        p = self.note()
        before = p.read_text()
        d = self.vault / 'daily' / f'{DAY}.md'
        d.parent.mkdir()
        d.write_text('# Today\n## Notes\n- Preserve.\n')
        self.run_journal('finish', success=False)
        self.assertEqual(p.read_text(), before)
        self.assertEqual(d.read_text(), '# Today\n## Notes\n- Preserve.\n')

    def test_verify_requires_both_project_and_daily_entry(self):
        self.run_journal('verify', success=False)
        p = self.note()
        p.write_text(p.read_text().replace('IN PROGRESS', 'DONE'))
        self.run_journal('verify', 'PP-97', '--completed', success=False)
        self.assertFalse((self.vault / 'daily').exists())

    def test_generic_branch_is_a_safe_filename(self):
        self.run_journal('finish', 'feature/add-journaling')
        self.run_journal('verify', 'feature/add-journaling', '--completed')
        self.assertEqual(len(list((self.vault / 'projects').glob('*.md'))), 1)

    def test_parallel_finishes_preserve_every_daily_entry(self):
        jobs = [subprocess.Popen([sys.executable, str(SCRIPT), 'finish', f'TEST-{i}',
                    '--vault', str(self.vault), '--date', DAY], stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, text=True) for i in range(6)]
        results = [(job, job.communicate(timeout=15)) for job in jobs]
        for job, (_, err) in results:
            self.assertEqual(job.returncode, 0, err)
        daily = (self.vault / 'daily' / f'{DAY}.md').read_text()
        for i in range(6):
            self.assertEqual(daily.count(f'[[TEST-{i}]]'), 1)

    def test_colliding_branch_names_cannot_complete_each_others_note(self):
        self.run_journal('start', 'feature/foo')
        p = self.vault / 'projects' / 'feature-foo.md'
        before = p.read_text()
        self.run_journal('finish', 'feature-foo', success=False)
        self.run_journal('verify', 'feature-foo', '--completed', success=False)
        self.assertEqual(before, p.read_text())
        self.assertFalse((self.vault / 'daily' / f'{DAY}.md').exists())

    def test_generic_branches_do_not_reuse_a_longer_name(self):
        self.run_journal('start', 'feature/add-journaling')
        self.run_journal('finish', 'feature/add')
        self.assertEqual(len(list((self.vault / 'projects').glob('*.md'))), 2)

    def test_invalid_multiline_input_does_not_create_notes(self):
        self.run_journal('finish', 'PP-97', '--summary', 'First line\nSecond line', success=False)
        self.assertFalse(self.vault.exists())

    def test_cleanup_stops_when_journaling_fails(self):
        root = Path(self.tmp.name) / 'repos'
        task = root / 'worktrees' / 'PP-97'
        (task / 'aorta').mkdir(parents=True)
        self.vault.write_text('Not a directory')
        result = subprocess.run(['zsh', str(ROOT / 'done-task.sh'), 'PP-97'],
            env={**os.environ, 'REPOS_ROOT': str(root), 'VAULT_ROOT': str(self.vault)},
            capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(task.exists(), 'Cleanup must not run after a journal failure')

    def test_cleanup_records_completion_before_removing_workspace(self):
        root = Path(self.tmp.name) / 'repos'
        task = root / 'worktrees' / 'PP-97'
        (task / 'aorta').mkdir(parents=True)
        result = subprocess.run(['zsh', str(ROOT / 'done-task.sh'), 'PP-97'],
            env={**os.environ, 'REPOS_ROOT': str(root), 'VAULT_ROOT': str(self.vault)},
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(task.exists())
        self.run_journal('verify', 'PP-97', '--completed', '--date', date.today().isoformat())

    def test_start_script_journals_before_opening_editor(self):
        root = Path(self.tmp.name) / 'repos'
        (root / 'aorta' / '.git').mkdir(parents=True)
        commands = Path(self.tmp.name) / 'bin'
        commands.mkdir()
        git = commands / 'git'
        git.write_text("#!/usr/bin/env python3\nimport pathlib, sys\na=sys.argv[1:]\nif 'worktree' in a and 'add' in a: pathlib.Path(a[a.index('add')+1]).mkdir(parents=True)\n")
        git.chmod(0o755)
        code = commands / 'code'
        code.write_text('#!/bin/sh\ntest -f "$VAULT_ROOT/projects/PP-97.md"\n')
        code.chmod(0o755)
        result = subprocess.run(['zsh', str(ROOT / 'new-task.sh'), 'PP-97', 'aorta'],
            env={**os.environ, 'PATH': str(commands) + os.pathsep + os.environ['PATH'],
                 'REPOS_ROOT': str(root), 'VAULT_ROOT': str(self.vault)},
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.run_journal('verify')


if __name__ == '__main__':
    unittest.main()

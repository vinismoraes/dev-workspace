#!/usr/bin/env python3
"""Record and verify task milestones in Obsidian, without cleaning up worktrees."""
import argparse
from datetime import date
import fcntl
import os
from pathlib import Path
import re
import sys
import tempfile

DAILY = '''# {day}

## Plan

```dataview
TASK
FROM #staff-track
WHERE !completed
GROUP BY file.link
```

## Activity
-

## Notes
-
'''


def section(text, heading):
    matches = list(re.finditer(r'^' + re.escape(heading) + r'\r?$', text, re.M))
    if len(matches) != 1:
        raise ValueError(f'Expected exactly one {heading} section; repair the note manually')
    start = matches[0].end()
    following = re.search(r'^## ', text[start:], re.M)
    return start, start + following.start() if following else len(text)


def append_entry(text, heading, entry):
    start, end = section(text, heading)
    body = text[start:end]
    if entry in body.splitlines():
        return text
    # Preserve all existing entries, including the placeholder, verbatim.
    return text[:end].rstrip('\n') + '\n' + entry + '\n\n' + text[end:]


def field(text, name, value):
    pattern = r'^\*\*' + re.escape(name) + r'\*\*:.*$'
    if len(re.findall(pattern, text, re.M)) != 1:
        raise ValueError(f'Expected exactly one {name} field; repair the project note manually')
    return re.sub(pattern, lambda _: f'**{name}**: {value}', text, flags=re.M)


def save(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError('Refusing to replace a symlinked note')
    if path.exists() and path.read_text() == text:
        return
    fd, tmp = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(text)
        if path.exists():
            os.chmod(tmp, path.stat().st_mode & 0o777)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def project(vault, branch, title, repos):
    ticket = re.search(r'(?<![A-Z0-9])[A-Z][A-Z0-9]*-\d+(?!\d)', branch)
    identity = ticket.group() if ticket else re.sub(r'[^\w.-]+', '-', branch).strip('.-')
    if not identity:
        raise ValueError('Branch must contain a usable task name')
    boundary = r'(?:$|[\s—–-])' if ticket else r'(?:$|\s)'
    matches = sorted(p for p in (vault / 'projects').glob('*.md')
                     if re.match(re.escape(identity) + boundary, p.stem))
    if len(matches) > 1:
        raise ValueError(f'Multiple project notes match {identity}; resolve ambiguity first')
    name = identity + (' ' + re.sub(r'[/\\\[\]|#]+', '-', title) if title else '')
    p = matches[0] if matches else vault / 'projects' / (name + '.md')
    if p.is_symlink():
        raise ValueError('Refusing to replace a symlinked note')
    if p.exists():
        text = p.read_text()
        if not ticket and f'**Branch**: {branch}' not in text.splitlines():
            raise ValueError('Generic task filename collides with another branch; resolve the note name manually')
        return p, text
    ticket_line = f'**Ticket**: https://everlong.atlassian.net/browse/{identity}\n' if ticket else ''
    return p, (f'# {name}\n#task\n\n{ticket_line}**Branch**: {branch}\n'
               f'**Status**: IN PROGRESS\n**Repos**: {", ".join(repos)}\n\n'
               '## Context\n\n## Key PRs\n\n## Decisions\n\n## Learnings\n')


def completion_present(text, heading, prefix):
    start, end = section(text, heading)
    return any(line == prefix or line.startswith(prefix + ' ') for line in text[start:end].splitlines())


def journal(args):
    vault = args.vault.expanduser()
    if args.action != 'verify':
        vault.mkdir(parents=True, exist_ok=True)
    if not vault.is_dir():
        raise ValueError('Vault does not exist or is not a directory')
    # Serialize cooperating agents so concurrent daily entries cannot overwrite each other.
    # Verification uses the same lock but never creates notes or repairs missing entries.
    with (vault / '.task-journal.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        p, text = project(vault, args.branch, args.title, args.repo)
        daily = vault / 'daily' / (args.date + '.md')
        prefix = f'- Completed [[{p.stem}]].'
        if args.action == 'verify':
            if not p.exists():
                raise ValueError('Project note is missing')
            expected = 'DONE' if args.completed else 'IN PROGRESS'
            if f'**Status**: {expected}' not in text.splitlines():
                raise ValueError(f'Project status must be {expected}')
            if not args.completed and f'**Branch**: {args.branch}' not in text.splitlines():
                raise ValueError('Project branch does not match the requested task')
            if args.completed and (not daily.exists() or not completion_present(daily.read_text(), '## Activity', prefix)):
                raise ValueError('Daily completion entry is missing for the requested date')
        elif args.action == 'start':
            text = field(field(text, 'Status', 'IN PROGRESS'), 'Branch', args.branch)
            save(p, text)
            if p.read_text() != text:
                raise ValueError('Project note verification failed')
        else:
            # Validate both notes before writing either. Write daily first so a failed
            # daily write never marks the project DONE without recording the activity.
            text = field(text, 'Status', 'DONE')
            context_prefix = f'- {args.date}: Task completed.'
            if not completion_present(text, '## Context', context_prefix):
                text = append_entry(text, '## Context', context_prefix + (' ' + args.summary if args.summary else ''))
            day_text = daily.read_text() if daily.exists() else DAILY.format(day=args.date)
            if not completion_present(day_text, '## Activity', prefix):
                day_text = append_entry(day_text, '## Activity', prefix + (' ' + args.summary if args.summary else ''))
            save(daily, day_text)
            save(p, text)
            if p.read_text() != text or daily.read_text() != day_text:
                raise ValueError('Written note verification failed')
    print(f'Journal {args.action} verified: {p}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('start', 'finish', 'verify'))
    parser.add_argument('branch')
    parser.add_argument('--vault', type=Path, default=Path(os.environ.get('VAULT_ROOT', '~/ObsidianVault')))
    parser.add_argument('--date', default=date.today().isoformat(), help='Local YYYY-MM-DD; pass explicitly when backfilling')
    parser.add_argument('--title', default='')
    parser.add_argument('--repo', action='append', default=[])
    parser.add_argument('--summary', default='', help='One factual sentence; no sensitive data')
    parser.add_argument('--completed', action='store_true', help='Verify DONE status and today\'s completion entry')
    args = parser.parse_args()
    try:
        date.fromisoformat(args.date)
        if any('\n' in x or '\r' in x for x in [args.branch, args.title, args.summary, *args.repo]):
            raise ValueError('Task fields must be single-line values')
        journal(args)
    except (OSError, ValueError) as error:
        print(f'Obsidian journaling failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

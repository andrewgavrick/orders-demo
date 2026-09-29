const { execFileSync } = require('node:child_process');
const { readFileSync } = require('node:fs');

const subjectPattern = /^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9][a-z0-9._/-]*\))?!?: \S(?:.*\S)?$/u;

function isValidSubject(subject) {
  return subjectPattern.test(subject);
}

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8' }).trim();
}

function main() {
  const event = JSON.parse(readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
  let revisions;

  if (process.env.GITHUB_EVENT_NAME === 'pull_request') {
    revisions = [`${event.pull_request.base.sha}..${event.pull_request.head.sha}`];
  } else if (process.env.GITHUB_EVENT_NAME === 'push') {
    if (event.deleted) return;
    // A new branch has no previous tip. Avoid linting unrelated legacy history.
    revisions = /^0+$/.test(event.before)
      ? ['-1', event.after]
      : [`${event.before}..${event.after}`];
  } else {
    throw new Error(`Unsupported event: ${process.env.GITHUB_EVENT_NAME}`);
  }

  const commits = git('rev-list', '--no-merges', ...revisions).split('\n').filter(Boolean);
  const invalid = commits.filter((sha) => {
    const subject = git('show', '-s', '--format=%s', sha);
    if (isValidSubject(subject)) return false;
    console.error(`Invalid commit ${sha.slice(0, 12)}: ${JSON.stringify(subject)}`);
    return true;
  });

  if (invalid.length) {
    console.error('Expected type(scope): description. Scope is optional; ! marks a breaking change.');
    console.error('Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.');
    console.error('Example: refactor(orders): move payment logic into services');
    process.exitCode = 1;
  } else {
    console.log(`Validated ${commits.length} commit subject(s).`);
  }
}

module.exports = { isValidSubject };
if (require.main === module) main();

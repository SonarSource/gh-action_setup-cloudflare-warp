import { spawn } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { EOL } from 'node:os';

// Check if we're in post-execution phase
if (process.env.STATE_POST) {
  // Run cleanup command
  run(process.env.INPUT_POST);
} else {
  // Mark that main has run (enables post execution)
  appendFileSync(process.env.GITHUB_STATE, `POST=true${EOL}`);
  // Run main command
  run(process.env.INPUT_MAIN);
}

function run(command) {
  const child = spawn(command, { shell: true, stdio: 'inherit' });
  child.on('exit', code => process.exit(code || 0));
}

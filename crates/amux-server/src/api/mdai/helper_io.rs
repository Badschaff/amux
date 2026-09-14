//! Synchronous model helpers need concurrent, deadline-bound pipe I/O. No
//! reader/writer threads may outlive the call, even if a descendant holds EOF.

use std::{
    io::{self, Read, Write},
    os::{fd::AsRawFd, unix::process::CommandExt},
    process::{Child, Command, Output, Stdio},
    time::{Duration, Instant},
};

#[derive(Debug)]
pub(super) enum Error {
    Spawn(io::Error),
    Io(io::Error),
    Timeout {
        written: usize,
        stdout: usize,
        stderr: usize,
    },
    OutputLimit {
        limit: usize,
    },
    IncompleteInput {
        written: usize,
        total: usize,
    },
}

struct OwnedChild {
    child: Child,
    reaped: bool,
}

impl Drop for OwnedChild {
    fn drop(&mut self) {
        if !self.reaped {
            // This helper gets its own group at spawn. Keep its PID waitable
            // until all pipes close, so a completed parent cannot free/reuse
            // the group identity while its descendants still hold the pipes.
            let pid = self.child.id();
            // SAFETY: pid is the positive leader of the group we just spawned.
            let group_signalled = unsafe { libc::kill(-(pid as i32), libc::SIGKILL) } == 0;
            let _ = self.child.kill();
            let reaped = self.child.wait().is_ok();
            tracing::info!(target: "amux::model_helper", pid, group_signalled, reaped,
                measured = true, n_considered = 1, verdict = "helper_io_cleanup",
                "stopped helper after incomplete pipe I/O");
        }
    }
}

fn nonblocking(pipe: &impl AsRawFd) -> Result<(), Error> {
    // SAFETY: the pipe owns this descriptor for both calls; preserve its flags.
    let flags = unsafe { libc::fcntl(pipe.as_raw_fd(), libc::F_GETFL) };
    if flags == -1
        || unsafe { libc::fcntl(pipe.as_raw_fd(), libc::F_SETFL, flags | libc::O_NONBLOCK) } == -1
    {
        return Err(Error::Io(io::Error::last_os_error()));
    }
    Ok(())
}

fn drain(
    pipe: &mut Option<impl Read>,
    out: &mut Vec<u8>,
    other_len: usize,
    limit: usize,
) -> Result<bool, Error> {
    let mut progressed = false;
    let mut buf = [0; 8192];
    // Fairness: even a continuous producer must yield to stdin, the other
    // output stream and the deadline. Retention has a separate explicit cap.
    for _ in 0..32 {
        let Some(reader) = pipe.as_mut() else { break };
        match reader.read(&mut buf) {
            Ok(0) => {
                *pipe = None;
                break;
            }
            Ok(n) => {
                if n > limit.saturating_sub(out.len()).saturating_sub(other_len) {
                    return Err(Error::OutputLimit { limit });
                }
                out.extend_from_slice(&buf[..n]);
                progressed = true;
            }
            Err(e) if e.kind() == io::ErrorKind::WouldBlock => break,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(Error::Io(e)),
        }
    }
    Ok(progressed)
}

pub(super) fn run(
    mut cmd: Command,
    prompt: &[u8],
    budget: Duration,
    limit: usize,
) -> Result<Output, Error> {
    let started = Instant::now();
    cmd.process_group(0)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut owned = OwnedChild {
        child: cmd.spawn().map_err(Error::Spawn)?,
        reaped: false,
    };
    let mut input = owned.child.stdin.take();
    let mut output = owned.child.stdout.take();
    let mut errors = owned.child.stderr.take();
    if let Some(p) = &input {
        nonblocking(p)?;
    }
    if let Some(p) = &output {
        nonblocking(p)?;
    }
    if let Some(p) = &errors {
        nonblocking(p)?;
    }
    let mut written = 0;
    let (mut stdout, mut stderr) = (Vec::new(), Vec::new());
    loop {
        if started.elapsed() >= budget {
            return Err(Error::Timeout {
                written,
                stdout: stdout.len(),
                stderr: stderr.len(),
            });
        }
        let mut progressed = false;
        if written == prompt.len() {
            input = None;
        }
        if let Some(pipe) = input.as_mut() {
            let end = written.saturating_add(65536).min(prompt.len());
            match pipe.write(&prompt[written..end]) {
                Ok(0) => input = None,
                Ok(n) => {
                    written += n;
                    progressed = true;
                }
                Err(e) if e.kind() == io::ErrorKind::BrokenPipe => input = None,
                Err(e)
                    if matches!(
                        e.kind(),
                        io::ErrorKind::WouldBlock | io::ErrorKind::Interrupted
                    ) => {}
                Err(e) => return Err(Error::Io(e)),
            }
        }
        if written == prompt.len() {
            input = None;
        }
        progressed |= drain(&mut output, &mut stdout, stderr.len(), limit)?;
        progressed |= drain(&mut errors, &mut stderr, stdout.len(), limit)?;
        // Do not reap an exited parent while inherited pipes remain open.
        // Its reserved PID makes group cleanup safe if those pipes time out.
        if input.is_none() && output.is_none() && errors.is_none() {
            if let Some(status) = owned.child.try_wait().map_err(Error::Io)? {
                owned.reaped = true;
                if status.success() && written != prompt.len() {
                    return Err(Error::IncompleteInput {
                        written,
                        total: prompt.len(),
                    });
                }
                return Ok(Output {
                    status,
                    stdout,
                    stderr,
                });
            }
        }
        if !progressed {
            std::thread::sleep(
                Duration::from_millis(5).min(budget.saturating_sub(started.elapsed())),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn output_limit_fails_explicitly_without_retaining_the_full_stream() {
        let mut cmd = Command::new("/bin/sh");
        cmd.args([
            "-c",
            "cat >/dev/null; dd if=/dev/zero bs=65536 count=32 2>/dev/null",
        ]);
        assert!(matches!(
            run(cmd, b"request", Duration::from_secs(2), 1024),
            Err(Error::OutputLimit { limit: 1024 })
        ));
    }

    #[test]
    fn successful_exit_does_not_hide_an_incomplete_prompt() {
        let mut cmd = Command::new("/bin/sh");
        cmd.args(["-c", "exec 0<&-; printf answer"]);
        assert!(matches!(
            run(
                cmd,
                &vec![b'x'; 2 * 1024 * 1024],
                Duration::from_secs(2),
                1024
            ),
            Err(Error::IncompleteInput { .. })
        ));
    }

    #[test]
    fn large_prompt_and_output_can_progress_in_opposite_directions() {
        let mut cmd = Command::new("/bin/sh");
        cmd.args(["-c", "dd if=/dev/zero bs=65536 count=8 2>/dev/null; wc -c"]);
        let out = run(
            cmd,
            &vec![b'x'; 2 * 1024 * 1024],
            Duration::from_secs(3),
            1024 * 1024,
        )
        .unwrap();
        assert!(out.status.success());
        assert_eq!(
            String::from_utf8_lossy(&out.stdout[8 * 65536..]).trim(),
            "2097152"
        );
    }

    #[test]
    fn failed_early_exit_preserves_diagnostics_even_with_incomplete_input() {
        let mut cmd = Command::new("/bin/sh");
        cmd.args(["-c", "exec 0<&-; printf quota >&2; exit 7"]);
        let out = run(
            cmd,
            &vec![b'x'; 2 * 1024 * 1024],
            Duration::from_secs(2),
            1024,
        )
        .unwrap();
        assert_eq!(out.status.code(), Some(7));
        assert_eq!(out.stderr, b"quota");
    }

    #[test]
    fn deadline_stops_the_owned_group_and_preserves_a_peer() {
        let dir = tempfile::tempdir().unwrap();
        let marker = dir.path().join("descendant-ran");
        let mut peer = Command::new("sleep").arg("5").spawn().unwrap();
        let mut cmd = Command::new("/bin/sh");
        cmd.args([
            "-c",
            "(sleep 0.4; printf leaked > \"$1\") & printf ready",
            "helper-fixture",
        ])
        .arg(&marker);
        let result = run(cmd, b"", Duration::from_millis(100), 1024);
        std::thread::sleep(Duration::from_millis(500));
        let peer_alive = peer.try_wait().unwrap().is_none();
        let _ = peer.kill();
        let _ = peer.wait();
        assert!(matches!(result, Err(Error::Timeout { .. })));
        assert!(!marker.exists(), "a timed-out descendant continued writing");
        assert!(peer_alive, "helper cleanup affected an unrelated process");
    }
}

//go:build darwin || linux

package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"syscall"
)

func replaceProcess(name string, args ...string) error {
	path, err := exec.LookPath(name)
	if err != nil {
		return err
	}
	return syscall.Exec(path, append([]string{name}, args...), os.Environ())
}

func attachedCommand(name string, args ...string) *exec.Cmd {
	cmd := exec.Command(name, args...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd
}

type signalExit syscall.Signal

func (s signalExit) Error() string { return fmt.Sprintf("interrupted by signal %d", s) }

func exitCode(err error) int {
	var interrupted signalExit
	if errors.As(err, &interrupted) {
		return 128 + int(interrupted)
	}
	var child *exec.ExitError
	if errors.As(err, &child) {
		status := child.Sys().(syscall.WaitStatus)
		if status.Signaled() {
			return 128 + int(status.Signal())
		}
		return child.ExitCode()
	}
	if errors.Is(err, exec.ErrNotFound) || errors.Is(err, os.ErrNotExist) {
		return 127
	}
	return 1
}

// Keep the parent alive during multi-command workflows so it can restore the
// original branch. Children share the terminal and receive forwarded signals.
type commandSession struct {
	signals     chan os.Signal
	interrupted os.Signal
}

func newCommandSession() *commandSession {
	s := &commandSession{signals: make(chan os.Signal, 8)}
	signal.Notify(s.signals, os.Interrupt, syscall.SIGTERM)
	return s
}

func (s *commandSession) close() { signal.Stop(s.signals) }

func (s *commandSession) cancellation() error {
	select {
	case sig := <-s.signals:
		s.interrupted = sig
	default:
	}
	if s.interrupted != nil {
		return signalExit(s.interrupted.(syscall.Signal))
	}
	return nil
}

func (s *commandSession) run(name string, args ...string) error {
	if err := s.cancellation(); err != nil {
		return err
	}
	cmd := attachedCommand(name, args...)
	if err := cmd.Start(); err != nil {
		return err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	for {
		select {
		case sig := <-s.signals:
			s.interrupted = sig
			_ = cmd.Process.Signal(sig)
		case err := <-done:
			if interrupted := s.cancellation(); interrupted != nil {
				return interrupted
			}
			return err
		}
	}
}

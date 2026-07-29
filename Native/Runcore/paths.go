package runcore

import (
	"errors"
	"os"
	"path/filepath"
	"runtime"
)

// DefaultRootDir returns an OS-appropriate directory for persistent app state.
// It is intended for configs/identity/storage (not user documents).
//
// Override with RUNCORE_DIR if you want a custom location.
func DefaultRootDir(appName string) (string, error) {
	if v := os.Getenv("RUNCORE_DIR"); v != "" {
		return v, nil
	}
	if appName == "" {
		return "", errors.New("appName is empty")
	}

	// macOS/iOS: ~/Library/Application Support/<app>
	// Windows: %LOCALAPPDATA%\<app>
	// Linux: $XDG_STATE_HOME/<app> or ~/.local/state/<app>
	// Android: depends on embedding; os.UserConfigDir() usually works under gomobile,
	// otherwise the host app should pass an explicit Dir.
	switch runtime.GOOS {
	case "windows":
		if base := os.Getenv("LOCALAPPDATA"); base != "" {
			return filepath.Join(base, appName), nil
		}
		// Fallback to roaming if LOCALAPPDATA isn't set.
		if base, err := os.UserConfigDir(); err == nil && base != "" {
			return filepath.Join(base, appName), nil
		}
	case "linux":
		if base := os.Getenv("XDG_STATE_HOME"); base != "" {
			return filepath.Join(base, appName), nil
		}
		if home, err := os.UserHomeDir(); err == nil && home != "" {
			return filepath.Join(home, ".local", "state", appName), nil
		}
	case "android":
		if base, err := os.UserConfigDir(); err == nil && base != "" {
			return filepath.Join(base, appName), nil
		}
		if base := os.Getenv("TMPDIR"); base != "" {
			return filepath.Join(base, appName), nil
		}
	default:
		if base, err := os.UserConfigDir(); err == nil && base != "" {
			return filepath.Join(base, appName), nil
		}
	}

	// Last resort: current directory.
	return filepath.Join(".", "."+appName), nil
}


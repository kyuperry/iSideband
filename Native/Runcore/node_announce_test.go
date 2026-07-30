package runcore

import (
	"testing"
	"time"
)

func TestStartPeriodicAnnounceCanBeSkippedByEmbeddingClient(t *testing.T) {
	node := &Node{
		opts: Options{
			DisablePeriodicAnnounce: true,
		},
	}

	if !node.opts.DisablePeriodicAnnounce {
		t.Fatal("embedding client must be able to own the announcement schedule")
	}
	if node.announceStop != nil {
		t.Fatal("announcement timer unexpectedly started")
	}
}

func TestStartPeriodicAnnounceCreatesSharedWatchdogStopChannel(t *testing.T) {
	node := &Node{}
	node.startPeriodicAnnounce(time.Hour)
	t.Cleanup(func() {
		node.announceStopOnce.Do(func() {
			close(node.announceStop)
		})
	})

	if node.announceStop == nil {
		t.Fatal("announcement timer did not create its stop channel")
	}
}

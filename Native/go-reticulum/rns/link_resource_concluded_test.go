package rns

import (
	"sync/atomic"
	"testing"
	"time"
)

func TestResourceConcludedNotifiesOnlyOnce(t *testing.T) {
	var calls atomic.Int32
	resource := &Resource{
		size:                100,
		startedTransferring: time.Now().Add(-time.Second),
	}
	link := &Link{
		incomingResources: []*Resource{resource},
	}
	link.callbacks.ResourceConcluded = func(*Resource) {
		calls.Add(1)
	}

	link.ResourceConcluded(resource)
	link.ResourceConcluded(resource)

	deadline := time.Now().Add(time.Second)
	for calls.Load() == 0 && time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}
	if got := calls.Load(); got != 1 {
		t.Fatalf("completion callback count=%d want 1", got)
	}
}

package lfs

// Batcher provides a way to process a set of items in groups of n. Items can
// be added to the batcher from multiple goroutines and pulled off in groups
// when one of the following conditions occurs:
//   * The batch size is reached
//   * Flush() is called
//   * Exit() is called
// When a timeout, Flush(), or Exit() occurs, the group may be smaller than the
// batch size.
type Batcher struct {
	batchSize  int
	input      chan Transferable
	batchReady chan []Transferable
}

// NewBatcher creates a Batcher with the batchSize.
func NewBatcher(batchSize int) *Batcher {
	b := &Batcher{
		batchSize:  batchSize,
		input:      make(chan Transferable, batchSize),
		batchReady: make(chan []Transferable),
	}

	go b.acceptInput()
	return b
}

// Add adds an item to the batcher. Add is safe to call from multiple
// goroutines.
func (b *Batcher) Add(t Transferable) {
	b.input <- t
}

// Next will wait for the one of the above batch triggers to occur and return
// the accumulated batch.
func (b *Batcher) Next() []Transferable {
	return <-b.batchReady
}

// Exit stops all batching and allows Next() to return. Calling Add() after
// calling Exit() will result in a panic.
func (b *Batcher) Exit() {
	close(b.input)
}

// acceptInput runs in its own goroutine and accepts input from external
// clients. It fills and dispenses batches in a sequential order: for a batch
// size N, N items will be processed before a new batch is ready.
func (b *Batcher) acceptInput() {
	exit := false

	for {
		batch := b.newBatch()
	Loop:
		for len(batch) < b.batchSize {
			t, ok := <-b.input
			if !ok {
				exit = true // input channel was closed by Exit()
				break Loop
			}

			batch = append(batch, t)
		}

		b.batchReady <- batch

		if exit {
			return
		}
	}
}

// newBatch allocates a slice of Transferables with the capacity of the set
// batch size.
func (b *Batcher) newBatch() []Transferable {
	return make([]Transferable, 0, b.batchSize)
}

package obfs

import (
	"bytes"
	"testing"
)

func TestSalamanderRoundTrip(t *testing.T) {
	ob, err := newSalamanderObfuscator([]byte("a sufficiently long test key"))
	if err != nil {
		t.Fatal(err)
	}
	plain := []byte("example QUIC payload")
	encoded := make([]byte, len(plain)+smSaltLen)
	n := ob.Obfuscate(plain, encoded)
	if n != len(encoded) {
		t.Fatalf("Obfuscate length = %d, want %d", n, len(encoded))
	}
	if bytes.Equal(plain, encoded[smSaltLen:]) {
		t.Fatal("payload unexpectedly remained unchanged")
	}
	decoded := make([]byte, len(plain))
	got := ob.Deobfuscate(encoded[:n], decoded)
	if got != len(plain) || !bytes.Equal(decoded, plain) {
		t.Fatalf("round trip mismatch: got %q, want %q", decoded[:got], plain)
	}
}

func TestSalamanderUsesDifferentSalts(t *testing.T) {
	ob, err := newSalamanderObfuscator([]byte("a sufficiently long test key"))
	if err != nil {
		t.Fatal(err)
	}
	plain := []byte("same payload")
	first := make([]byte, len(plain)+smSaltLen)
	second := make([]byte, len(plain)+smSaltLen)
	if ob.Obfuscate(plain, first) == 0 || ob.Obfuscate(plain, second) == 0 {
		t.Fatal("obfuscation failed")
	}
	if bytes.Equal(first[:smSaltLen], second[:smSaltLen]) {
		t.Fatal("two packets received the same salt")
	}
	if bytes.Equal(first, second) {
		t.Fatal("identical packets produced identical wire bytes")
	}
}

func TestSalamanderRejectsShortPSK(t *testing.T) {
	if _, err := newSalamanderObfuscator([]byte("abc")); err != ErrPSKTooShort {
		t.Fatalf("error = %v, want %v", err, ErrPSKTooShort)
	}
}

func TestSalamanderRejectsShortInput(t *testing.T) {
	ob, err := newSalamanderObfuscator([]byte("a sufficiently long test key"))
	if err != nil {
		t.Fatal(err)
	}
	if got := ob.Deobfuscate([]byte{1, 2, 3}, make([]byte, 16)); got != 0 {
		t.Fatalf("Deobfuscate length = %d, want 0", got)
	}
	if got := ob.Obfuscate([]byte("payload"), make([]byte, 3)); got != 0 {
		t.Fatalf("Obfuscate length = %d, want 0", got)
	}
}

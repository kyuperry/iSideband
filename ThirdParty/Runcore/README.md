# Runcore integration

iSideband links a locally built `Runcore.xcframework` based on:

- `github.com/svanichkin/runcore`
- `github.com/svanichkin/go-reticulum` v1.0.4
- `github.com/svanichkin/go-lxmf` v0.9.3

The framework includes a small raw-packet C bridge so iSideband can retain
ownership of its CoreBluetooth RNode connection while the Go core handles
Reticulum transport, Links and LXMF.

The upstream projects are distributed under the MIT license.

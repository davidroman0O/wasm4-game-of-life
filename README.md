# Game Of Life

Game Of Life written in Zig for the [WASM-4](https://wasm4.org) fantasy console.

![Drag Racing](./img/gameoflife.PNG)

## Building

Build the cart by running:

```shell
zig build -Drelease-small=true
```

Then run it with:

```shell
w4 run zig-out/lib/cart.wasm
```

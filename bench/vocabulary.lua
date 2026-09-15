return {
    resources = { Cell = { destroy = 'bench_release' } },
    hosts = {
        acquire = { symbol = 'bench_acquire', result = 'Cell', stages = {{ constraint = 'Int' }} },
        peek = { symbol = 'bench_peek', result = 'Int', stages = {{ constraint = 'Cell' }} },
    },
}


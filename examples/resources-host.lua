return {
    resources = { Buffer = { destroy = 'app_close' } },
    hosts = {
        open_buffer = { symbol = 'app_open', result = 'Buffer',
            stages = { { constraint = 'Int' } } },
        buffer_size = { symbol = 'app_size', result = 'Int',
            stages = { { constraint = 'Buffer', capability = 'read' } } },
    },
}


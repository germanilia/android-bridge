# Project-local MLX Whisper wrapper

Meeting Capture uses `mac/Tools/mlx_whisper/bin/mlx_whisper` as the project-local entry point.
Install its Python dependency in the Mac development environment with:

```sh
python3 -m pip install -r mac/Tools/mlx_whisper/requirements.txt
```

This imports the previously discovered local `mlx_whisper` CLI shape into this repo without runtime dependency on another project path.

"""HelloWorld application - dataset-independent smoke test."""

import shlex

from omics_apps.base import MultiOmicsApp


class HelloWorldApp(MultiOmicsApp):
    """Writes a configurable message and a sample count to a text file."""

    name = "HelloWorld"
    category = "Development"
    description = "Hello world — runs on any dataset, writes a text file output"
    required_columns = []

    params_definition = [
        {"name": "cores", "type": "select", "default": 1, "options": [1, 2, 4, 8], "required": True, "description": "Number of CPU cores"},
        {"name": "ram", "type": "integer", "default": 4, "description": "RAM in GB"},
        {"name": "scratch", "type": "integer", "default": 10, "description": "Scratch space in GB"},
        {"name": "partition", "type": "select", "default": "employee", "options": ["employee", "normal"], "description": "Cluster partition"},
        {"name": "message", "type": "string", "default": "Hello, MultiOmicsStudio!", "description": "Message to write into the output file"},
    ]

    def commands(self) -> str:
        message = shlex.quote(self.params.get("message", "Hello, MultiOmicsStudio!"))
        n_samples = len(self.samples)
        return "\n".join([
            f"echo {message} > hello.txt",
            f"echo 'Dataset has {n_samples} sample(s)' >> hello.txt",
        ])

    def next_dataset(self) -> dict:
        return {
            "Name": "HelloWorld",
            "Output [File]": f"{self.result_dir}/hello.txt",
        }

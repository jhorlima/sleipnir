"""Samples `docker stats` of one compose service while a measured command runs."""

import subprocess
import threading

from parsers import parse_cpu_pct, parse_mem_mb


def container_ids(service):
    result = subprocess.run(
        ["docker", "ps", "-q", "--filter", f"label=com.docker.compose.service={service}"],
        capture_output=True, text=True,
    )
    return result.stdout.split()


def sample_once(service):
    """(mem_mb, cpu_pct) summed over the service's containers, or None when none is running."""
    ids = container_ids(service)
    if not ids:
        return None
    result = subprocess.run(
        ["docker", "stats", "--no-stream", "--format", "{{.MemUsage}}|{{.CPUPerc}}", *ids],
        capture_output=True, text=True,
    )
    mem_total = 0.0
    cpu_total = 0.0
    for line in result.stdout.splitlines():
        mem_cell, cpu_cell = line.split("|")
        mem_total += parse_mem_mb(mem_cell)
        cpu_total += parse_cpu_pct(cpu_cell)
    return mem_total, cpu_total


class StatsSampler:
    """Context manager. After exit: peak_mem_mb and avg_cpu_pct (None when no sample was taken).
    CPU is docker's figure: 100% is one full core."""

    def __init__(self, service):
        self.service = service
        self.samples = []
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._loop, daemon=True)

    def _loop(self):
        while not self._stop.is_set():
            sample = sample_once(self.service)
            if sample is not None:
                self.samples.append(sample)

    def __enter__(self):
        self._thread.start()
        return self

    def __exit__(self, *exc):
        self._stop.set()
        self._thread.join()

    @property
    def peak_mem_mb(self):
        if not self.samples:
            return None
        return round(max(mem for mem, _ in self.samples), 1)

    @property
    def avg_cpu_pct(self):
        if not self.samples:
            return None
        return round(sum(cpu for _, cpu in self.samples) / len(self.samples), 1)

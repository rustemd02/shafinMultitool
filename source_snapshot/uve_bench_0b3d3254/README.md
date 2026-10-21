---
license: cc-by-sa-4.0
---
# UVE-Bench
<!-- ![](./overview.png) -->
<p align="center">
  <img src="./overview.png" alt=overview width="800"/>
  <br>
  <i>Overview of UVE-Bench. (a) The distribution of video sources. (b) The distribution of data example over 15 fine-grained AIGV evaluation aspects. (c) The distribution of human preference over the four categories. (d) Data examples illustrating how to evaluate both single video rating and video pair comparison using the human preference annotations.</i>
</p>

UVE-Bench is a benchmark designed to assess the ability of MLLMs to evaluate AI-generated videos. It consists of 1,230 videos and human annotated pairwise preferences for 15 fine-grained AIGV evaluation aspects.

For example:
```python
{
    "video_a": "moviegen_480p/moviegen_480p_00000.mp4",
    "video_b": "mochi/mochi_00000.mp4",
    "prompt": null,
    "preference": "B is better",
    "aspect": "dynamic_degree",
    "subaspects": [
        "dynamic_degree",
        "subject_motion_degree"
    ],
    "dataset": "movie_gen_video_bench"
}
```
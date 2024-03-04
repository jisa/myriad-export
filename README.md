# Convert a PyTorch or an ONNX model to a Myriad blob

## Motivation

Luxonis cameras and Movidius Neural Compute sticks run a MyriadX VPU.
Custom models need to be converted to a "blob" format first to run on the VPU.

Unfortunately, the sequence of steps for PyTorch model conversion is somewhat
complicated. Even more unfortunately, Intel's OpenVino stopped supporting
Intel's Myriad VPUs in 2023
[[Release Notes](https://www.intel.com/content/www/us/en/developer/articles/release-notes/openvino-lts/2022-3.html),
[Discussion](https://discuss.luxonis.com/d/2642-compile-tool-for-openvino-20231/9)].

Therefore this docker-based tooling running old OpenVino and old Python in an
old Ubuntu. Given a PyTorch model, it produces a model in blob format for
MyriadX VPU.

If you have an ONNX model already, this tool can also support you by skipping
the PyTorch-to-ONNX conversion step and directly converting your ONNX model.

You may want to use [Blobconverter](https://blobconverter.luxonis.com/) by
Luxonis instead of this tool. You still need to figure out how to convert your
PyTorch model into a format that blobconverter accepts. See links in Resources
for inspiration.

## Instructions

### Installation

You need a working [Docker](https://docs.docker.com/) installation.

I am assuming you are using Linux or know how to translate the instructions
below to your favorite platform.

**Before** building the docker image, make sure that `USER_UID` and `USER_GID`
in `Dockerfile` match your real user and group id. You can get these by running
`id`. You don't need to modify `USER_NAME` in the `Dockerfile`.

```
$ docker-build.sh
```

### Running

```
# The PyTorch model must be in the current working directory or its
# subdirectory.
$ cd ${DIRECTORY_WITH_MY_MODEL}

# Model paths must be relative to the current directory.
$ ${SOME_PATH}/docker-run.sh \
        --input ${PYTORCH_INPUT_MODEL}|${ONNX_INPUT_MODEL} \
        --input-shape '[1, 3, 240, 320]' \
        --output ${BLOB_OUTPUT_MODEL}
```

Change the input shape to match your use case. Note the quotes.

ONNX models need .onnx file extension.

There are other flags you may want to set:

```$ ./docker-run.sh --help```

Most likely candidates for changing are:

  `--reverse-input-channels|--no-reverse-input-channels` is important. PyTorch
typically uses CHW tensors, whereas everything else, such as Luxonis cameras,
uses HWC. Reversing input channels helps you to feed correct data to a CHW
model. The tool is **not** reversing by default.  
  `--input-type`, in case your inputs to the final blob model are not unsigned
8-bit integers.  
[One of](https://github.com/openvinotoolkit/openvino/blob/cf2c7da568934870c29acc961a4498ff9cbd8d9c/tools/compile_tool/main.cpp#L175-L186)
`U8`, `U16`, `U32`, `U64`, `I8`, `I16`, `I32`, `I64`, `BF16`, `FP16`, `FP32`,
`BOOL` or `ONNX`. On a Luxonis camera with a Myriad chip, the inputs are
typically 8-bit images, so the default `U8` value should work. Use `ONNX` to use
the input type information from the exported model.  
  `--output-type`, in case you want other than FP16 outputs. Same options as
with `--input-type`.  
  `--mean 'input_layer_name=[123.675, 116.28, 103.53]'` automatically shifts the
input data.  
  `--scale 'input_layer_name=[58.4, 57.12, 57.38]` automatically rescales input
data. Mean adjustment happens before scale adjustment.  
  `--model-key` specifies, if loading a model from a dict, which key to use to
find the model entry. Defaults to `"model"`.  
  `--model-dtype` for casting model parameters before exporting to ONNX. One of
dtype names from PyTorch, such as `float16`, `float32`, `half`, etc. Defaults to
`float32`. In practice, blob compiler does not support float64 and is less
likely to work with float16. The final blob model will be in 16-bit floats
either way.  
  `--nshaves`, `--nslices`, `--nstreams` to match your VPU and intended usage.  
  `--new-export` to test your luck to the limits. The tool then uses a "modern"
onnx export method instead of a probably-soon-to-be-deprecated one. However,
as of January 2024 it cannot be restricted to an old opset that later stages
require.

## Advances usage

This is a hacker's tool. Edit `myriad-export.py`, rebuild the docker image, try
again. Unlike the first docker build, rebuilding after editing the script should
be fast.

If you want to automatically scale or shift the input, edit the script.
Specifically the "model optimization" parameters. Rebuild, run.

If you need a newer version of any of the python packages, such as PyTorch, edit
the `Dockerfile`, rebuild and fingers crossed. Keep in mind that the older
OpenVino may not support some newer ops. Newer OpenVino does not support Myriad
VPUs.

If you need to do things manually in the docker:

```
$ cd ${DIRECTORY_WITH_MY_MODEL}
$ ${SOME_PATH}/docker-bash.sh
```

For faster iterations, you can edit a copy of the conversion script is in
`/usr/local/bin`. The changes will disappear after you log out from the container,
unless you do something about it, such as `docker cp`, volume bind, `docker
commit` or similar.

The user `"user"` is set up for `sudo`. Password is "password", without the
quotes. If you want to turn this into a service and make it accessible from
the internet ... I clearly did not bother to make the Docker container secure
in any way.

## Missing features

* Aforementioned input transforms (shift, scaling). You can make them part of
your model or edit the conversion script.
* Input and output model layout modifications.
* Multiple input tensors.
* Model quantization or other ways to make the model leaner and faster.
* And [some more](https://github.com/openvinotoolkit/openvino/blob/cf2c7da568934870c29acc961a4498ff9cbd8d9c/tools/compile_tool/main.cpp#L574-L597).

## Support

If you have a problem, most likely you need to fix it yourself. Feel free to
share improvements and fixes.

## Useful resources in random order
* [OpenVino installation](https://docs.openvino.ai/2023.2/openvino_docs_install_guides_overview.html?VERSION=v_2022_3_1&ENVIRONMENT=RUNTIME&OP_SYSTEM=LINUX&DISTRIBUTION=ARCHIVE)
* [OpenVino Compile Tool](https://docs.openvino.ai/2022.3/openvino_inference_engine_tools_compile_tool_README.html) - the [obsolete tool](https://community.intel.com/t5/Intel-Distribution-of-OpenVINO/Compile-Tool-No-Longer-Included-With-Installation/m-p/1492129) that you absolutely need.
* [OpenVino Legacy Conversion API](https://docs.openvino.ai/2023.2/openvino_docs_MO_DG_Deep_Learning_Model_Optimizer_DevGuide.html)
* [OpenVino's Docker images](https://docs.openvino.ai/2023.2/openvino_docs_install_guides_installing_openvino_docker.html) - In case you want to play with something else.
* [Overview of Torch ONNX export](https://pytorch.org/docs/stable/onnx.html) - an important piece of the puzzle.
  * [Newer Torch ONNX export](https://pytorch.org/docs/stable/onnx_dynamo.html)
  * [Older Torch ONNX export](https://pytorch.org/tutorials/advanced/super_resolution_with_onnxruntime.html)
* [Blobconverter](https://github.com/luxonis/blobconverter/tree/master) - a webservice by Luxonis which converts different model types, excluding PyTorch, to Myriad blobs for their cameras.
* [Custom NN nodes by Luxonis](https://docs.luxonis.com/en/latest/pages/tutorials/creating-custom-nn-models/)
* [Deploying custom models by Luxonis](https://docs.luxonis.com/en/latest/pages/tutorials/deploying-custom-model/)
* [Model Conversion by Luxonis](https://docs.luxonis.com/en/latest/pages/model_conversion/)
* [Local Model Conversion by Luxonis](https://docs.luxonis.com/en/latest/pages/tutorials/local_convert_openvino/)
* [PyTorch-to-NCS2 How To](https://pemami4911.github.io/blog/2021/07/09/part-1-neural-compute-stick-2.html)
* [Another conversion tutorial for DepthAI](https://nifty-bartik-6a9295.netlify.app/tutorials/converting_openvino_model/)


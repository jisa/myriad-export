#!/usr/bin/env python3

import argparse
import json
import os
import pathlib
import subprocess
import sys
import tempfile

import onnx
import onnxsim
import openvino
import torch

if __name__ == '__main__':
    argparser = argparse.ArgumentParser()
    argparser.add_argument('--root', type=pathlib.Path,
                           default=pathlib.Path('/mnt/myriad'),
                           help='Working directory. Do not change unless you '
                                 'know what you are doing.')
    argparser.add_argument('--input', type=pathlib.Path, required=True,
                           help='Input PyTorch model.')
    argparser.add_argument('--model-key', default='model',
                           help='When loading a dict with a model, name the '
                                'key for the model.')
    argparser.add_argument('--input-shape', type=json.loads,
                           help='Shape of the input tensor. E.g. '
                                '[1, 3, 240, 320].')
    argparser.add_argument('--input-type', choices=[
        'U8', 'U16', 'U32', 'U64', 'I8', 'I16', 'I32', 'I64',
        'BF16', 'FP16', 'FP32', 'BOOL'],
                           default='U8', help='Input data type.')
    argparser.add_argument('--mean', type=json.loads,
                           help='Automatically center the input data. Mean '
                           'adjustment happens before rescaling.')
    argparser.add_argument('--scale', type=json.loads,
                           help='Automatically scale the input data. Scaling '
                           'happens after mean adjustment.')
    argparser.add_argument('--model-dtype', default='float32',
                           help='Data type of the input. One of PyTorch\'s '
                                'dtype strings.')
    argparser.add_argument('--reverse-input-channels',
                           dest='reverse_input_channels',
                           action='store_true',
                           help='Automatically convert HWC input into CHW')
    argparser.add_argument('--no-reverse-input-channels',
                           dest='reverse_input_channels', action='store_false',
                           help='Do NOT switch HWC input to CWH')
    argparser.set_defaults(reverse_input_channels=False)
    argparser.add_argument('--output', type=pathlib.Path, required=True,
                           help='Name of the output Myriad blob file.')
    argparser.add_argument('--nshaves', type=int, default=4,
                           help='Number of Myriad shaves.')
    argparser.add_argument('--nslices', type=int, default=4,
                           help='Number of Myriad slices.')
    argparser.add_argument('--nstreams', type=int, default=1,
                           help='Number of Myriad streams.')
    argparser.add_argument('--opset', type=int, default=12,
                           help='ONNX opset version.')
    argparser.add_argument('--new-export', default=False, action='store_true',
                           help='Use new Pytoch-to-Onnx export mode. '
                                'Unlikely to work.')
    args = argparser.parse_args()

    os.chdir(args.root)

    with tempfile.TemporaryDirectory() as workdir_name:
        workdir = pathlib.Path(workdir_name)

        if args.input.suffix == '.onnx':
            onnx_name = args.input
        else:
            print('Loading PyTorch model ...')
            model = torch.load(args.input, map_location='cpu')
            try:
                model = model[args.model_key]
            except (TypeError, KeyError):
                # Maybe we loaded a model itself and not a dict with a model?
                pass
            dtype = getattr(torch, args.model_dtype)
            try:
                model = model.eval().to(dtype=dtype)
            except AttributeError:
                if isinstance(model, dict):
                    print('Loaded a dict with the following keys: ' +
                          f'{list(model.keys())}')
                print('Could not load the model.\nFailed.')
                sys.exit(-1)
            dummy_input = torch.rand(args.input_shape, dtype=dtype)

            model_name = args.input.with_suffix('').name
            onnx_name = (workdir / model_name).with_suffix('.onnx')

            # https://pytorch.org/tutorials/advanced/super_resolution_with_onnxruntime.html
            print('Exporting to ONNX ...')
            if args.new_export:
                # As of 2024/01, Torch DynamoExport supports only opset=18 and does
                # not have a way to restrict to opset=12. This typically leads to
                # failures in later stages.
                export_options = torch.onnx.ExportOptions(
                        dynamic_shapes=False,
                        diagnostic_options=torch.onnx.DiagnosticOptions())
                export = torch.onnx.dynamo_export(
                        model, dummy_input, export_options=export_options)
                with open(onnx_name, 'wb') as onnx_file:
                    export.save(onnx_file)
            else:  # Old export method. Recommended.
                _ov_model = torch.onnx.export(
                        model,
                        dummy_input,
                        f=onnx_name,
                        export_params=True,
                        opset_version=args.opset,
                        do_constant_folding=True,
                        input_names=['input'],
                        output_names=['output'])

        print('Loading ONNX model ...')
        onnx_model = onnx.load(onnx_name)
        print('Simplifying ...')
        onnx_model, _ = onnxsim.simplify(onnx_model)
        print('Checking the ONNX model ...')
        onnx.checker.check_model(onnx_model)
        onnx.save(onnx_model, onnx_name)
        print('Optimizing ...')
        cmd = [
            'mo', '--framework', 'onnx', '--input_model', onnx_name,
            '--compress_to_fp16', '--output_dir', workdir_name]
        if args.reverse_input_channels:
            cmd.append('--reverse_input_channels')
        if args.mean is not None:
            cmd.append('--mean_values')
            cmd.append(f'{args.mean}')
        if args.scale is not None:
            cmd.append('--scale_values')
            cmd.append(f'{args.scale}')
        result = subprocess.run(cmd)
        if result.returncode != 0:
            print('Failed.')
            sys.exit(result.returncode)

        print ('Compiling from ONNX to Myriad Blob ...')
        CONFIG_NAME='/tmp/myriad.config'
        with open(CONFIG_NAME, 'w') as config_file:
            config_file.write(
                    f'MYRIAD_NUMBER_OF_SHAVES {args.nshaves}\n' +
                    f'MYRIAD_NUMBER_OF_CMX_SLICES {args.nslices}\n' +
                    f'MYRIAD_THROUGHPUT_STREAMS {args.nstreams}\n' +
                    'MYRIAD_ENABLE_MX_BOOT NO\n')
        envs = {'InferenceEngine_DIR': '/opt/intel/openvino/runtime/cmake',
                'OpenVINO_DIR': '/opt/intel/openvino/runtime/cmake',
                'INTEL_OPENVINO_DIR': '/opt/intel/openvino',
                'PYTHONPATH': '/opt/intel/openvino/python/python3.8:'
                              '/opt/intel/openvino/python/python3',
                'LD_LIBRARY_PATH':
                    '/opt/intel/openvino/tools/compile_tool:'
                    '/opt/intel/openvino/runtime/3rdparty/hddl/lib:'
                    '/opt/intel/openvino/runtime/lib/intel64',
                'ngraph_DIR': '/opt/intel/openvino/runtime/cmake',
                'HDDL_INSTALL_DIR': '/opt/intel/openvino/runtime/3rdparty/hddl'}
        cmd = ['/opt/intel/openvino/tools/compile_tool/compile_tool',
               '-m', f'{workdir / onnx_name.with_suffix(".xml").name}',
               '-o', args.output,
               '-d', 'MYRIAD',
               '-ip', args.input_type,
               '-c', CONFIG_NAME]
        result = subprocess.run(
            cmd,
            env = envs)
        print('Done.' if result.returncode == 0 else 'Failed.')
        sys.exit(result.returncode)

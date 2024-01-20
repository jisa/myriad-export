# syntax=docker/dockerfile:1

FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update ; \
    apt-get install -y --no-install-recommends python3 python3-venv python3-pip ipython3 wget libtbb2 libpugixml1v5 libgtk-3-0 libgl1 cmake pkg-config g++ gcc libc6-dev libgflags-dev zlib1g-dev nlohmann-json3-dev make curl sudo libusb-1.0-0 libtinfo5 less vim screen ; \
    apt-get clean
RUN cd tmp ; \
    wget https://storage.openvinotoolkit.org/repositories/openvino/packages/2022.3.1/linux/l_openvino_toolkit_ubuntu20_2022.3.1.9227.cf2c7da5689_x86_64.tgz ; \
    tar zxf l_openvino_toolkit_ubuntu20_2022.3.1.9227.cf2c7da5689_x86_64.tgz ; \
    mkdir /opt/intel ; \
    mv l_openvino_toolkit_ubuntu20_2022.3.1.9227.cf2c7da5689_x86_64 /opt/intel/openvino
#RUN pip3 install numpy==1.19.5 openvino-dev[onnx,pytorch]==2022.3.1 onnx==1.10.0 onnxruntime==1.10.0 onnxsim==0.4.35
RUN pip3 install numpy==1.24.4 onnx==1.15.0 onnxruntime==1.16.3 onnxsim==0.4.35 openvino-dev==2022.3.1 onnxscript==0.1.0.dev20240119
RUN pip3 install torch==2.1.2+cpu torchvision==0.16.2+cpu torchaudio==2.1.2+cpu --index-url https://download.pytorch.org/whl/cpu

RUN mkdir /mnt/myriad
ENTRYPOINT ["/usr/local/bin/myriad-export.py"]
CMD []

ARG USER_NAME=user
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid ${USER_GID} user
RUN useradd --uid ${USER_UID} --gid ${USER_GID} --create-home ${USER_NAME}
RUN adduser ${USER_NAME} sudo
RUN echo ${USER_NAME}:password | chpasswd
USER user
RUN echo "source /opt/intel/openvino/setupvars.sh" >> "/home/${USER_NAME}/.bashrc"
# No telemetry for Intel.
RUN opt_in_out --opt_out

USER root
ARG EXPORT_TOOL=/usr/local/bin/myriad-export.py
COPY ./myriad-export.py "$EXPORT_TOOL"
RUN chmod +x "${EXPORT_TOOL}"

USER user

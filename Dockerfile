# syntax=docker/dockerfile:1

FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update ; \
    apt-get install -y --no-install-recommends python3 python3-venv python3-pip ipython3 wget libtbb2 libpugixml1v5 libgtk-3-0 libgl1 cmake pkg-config g++ gcc libc6-dev libgflags-dev zlib1g-dev nlohmann-json3-dev make curl sudo libtinfo5 less vim screen ; \
    apt-get clean
RUN cd tmp ; \
    wget https://storage.openvinotoolkit.org/repositories/openvino/packages/2022.3.1/linux/l_openvino_toolkit_ubuntu20_2022.3.1.9227.cf2c7da5689_x86_64.tgz ; \
    tar zxf l_openvino_toolkit_ubuntu20_2022.3.1.9227.cf2c7da5689_x86_64.tgz ; \
    mkdir /opt/intel ; \
    mv l_openvino_toolkit_ubuntu20_2022.3.1.9227.cf2c7da5689_x86_64 /opt/intel/openvino
RUN apt-get clean
RUN pip3 --no-cache-dir install numpy==1.24.4 onnx==1.15.0 onnxruntime==1.16.3 onnxsim==0.4.35 openvino-dev==2022.3.1 onnxscript==0.1.0.dev20240119
RUN pip3 --no-cache-dir install torch==2.1.2+cpu torchvision==0.16.2+cpu torchaudio==2.1.2+cpu --index-url https://download.pytorch.org/whl/cpu

RUN mkdir /mnt/myriad
ENTRYPOINT ["/usr/local/bin/myriad-export.py"]
CMD []

ARG USER_NAME=user
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid ${USER_GID} user
RUN useradd --uid ${USER_UID} --gid ${USER_GID} --create-home ${USER_NAME}
RUN adduser ${USER_NAME} sudo
RUN adduser ${USER_NAME} users
RUN adduser ${USER_NAME} video
RUN echo ${USER_NAME}:password | chpasswd

ENV HDDL_INSTALL_DIR=/opt/intel/openvino/runtime/3rdparty/hddl
ENV InferenceEngine_DIR=/opt/intel/openvino/runtime/cmake
ENV LD_LIBRARY_PATH=/opt/intel/openvino/runtime/3rdparty/hddl/lib:/opt/intel/openvino/runtime/3rdparty/tbb/lib:/opt/intel/openvino/runtime/lib/intel64:/opt/intel/openvino/tools/compile_tool
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV PYTHONPATH=/opt/intel/openvino/python/python3.8:/opt/intel/openvino/python/python3
ENV TBB_DIR=/opt/intel/openvino/runtime/3rdparty/tbb/cmake
ENV ngraph_DIR=/opt/intel/openvino/runtime/cmake
ENV OpenVINO_DIR=/opt/intel/openvino/runtime/cmake
ENV INTEL_OPENVINO_DIR=/opt/intel/openvino
ENV PKG_CONFIG_PATH=/opt/intel/openvino/runtime/lib/intel64/pkgconfig

# There isan issue with docker, udev events, lubusb and OpenVINO.
# https://docs.openvino.ai/2023.3/openvino_docs_install_guides_installing_openvino_docker.html
# https://github.com/openvinotoolkit/docker_ci/blob/2022.3.1/dockerfiles/ubuntu20/openvino_cgvh_dev_2022.3.1.dockerfile
RUN apt-get install -y autoconf automake build-essential libtool unzip ; apt-get clean
WORKDIR "/opt"
RUN curl -L https://github.com/libusb/libusb/archive/v1.0.22.zip --output v1.0.22.zip && \
    unzip v1.0.22.zip && rm -rf v1.0.22.zip

WORKDIR "/opt/libusb-1.0.22"
RUN ./bootstrap.sh && \
    ./configure --disable-udev --enable-shared && \
    make -j4
WORKDIR "/opt/libusb-1.0.22/libusb"
RUN /bin/mkdir -p '/usr/local/lib' && \
    /bin/bash ../libtool   --mode=install /usr/bin/install -c   libusb-1.0.la '/usr/local/lib' && \
    /bin/mkdir -p '/usr/local/include/libusb-1.0' && \
    /usr/bin/install -c -m 644 libusb.h '/usr/local/include/libusb-1.0' && \
    /bin/mkdir -p '/usr/local/lib/pkgconfig'
WORKDIR /opt/libusb-1.0.22/
RUN /usr/bin/install -c -m 644 libusb-1.0.pc '/usr/local/lib/pkgconfig' && \
    mkdir -p /etc/udev/rules.d && \
    cp ${INTEL_OPENVINO_DIR}/install_dependencies/97-myriad-usbboot.rules /etc/udev/rules.d/ && \
    ldconfig


USER user
# No telemetry for Intel.
RUN opt_in_out --opt_out

USER root
ARG EXPORT_TOOL=/usr/local/bin/myriad-export.py
COPY ./myriad-export.py "$EXPORT_TOOL"
RUN chmod +x "${EXPORT_TOOL}"

USER user


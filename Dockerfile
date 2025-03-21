FROM ubuntu:22.04

ENV DEBIAN_FRONTEND noninteractive

ARG WINE_VERSION=winehq-staging
ARG PYTHON_VERSION=3.10.11
ARG PYTHON_SHORT_VERSION=310
ARG PYINSTALLER_VERSION=5.10.1
ARG GIT_VERSION=2.40.0

# we need wine for this all to work, so we'll use the PPA
RUN set -x \
    && dpkg --add-architecture i386 \
    && apt-get update -qy \
    && apt-get install --no-install-recommends -qfy apt-transport-https software-properties-common wget gpg-agent rename git \
    && wget -nv https://dl.winehq.org/wine-builds/winehq.key \
    && apt-key add winehq.key \
    && add-apt-repository 'https://dl.winehq.org/wine-builds/ubuntu/' \
    && apt-get update -qy \
    && apt-get install --no-install-recommends -qfy $WINE_VERSION winbind cabextract \
    && apt-get clean \
    && wget -nv https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
    && chmod +x winetricks \
    && mv winetricks /usr/local/bin

# wine settings
ENV WINEARCH win64
ENV WINEDEBUG fixme-all
ENV WINEPREFIX /wine

# PYPI repository location
ENV PYPI_URL=https://pypi.python.org/
# PYPI index location
ENV PYPI_INDEX_URL=https://pypi.python.org/simple

# install python in wine, using the msi packages to install, extracting
# the files directly, since installing isn't running correctly.
RUN set -x \
    && winetricks win7 \
    && for msifile in `echo core dev exe lib path pip tcltk tools`; do \
        wget -nv "https://www.python.org/ftp/python/$PYTHON_VERSION/amd64/${msifile}.msi"; \
        wine msiexec /i "${msifile}.msi" /qb "TARGETDIR=C:/Python${PYTHON_SHORT_VERSION}"; \
        rm ${msifile}.msi; \
    done \
    && cd /wine/drive_c/Python${PYTHON_SHORT_VERSION} \
    && echo "wine 'C:\Python${PYTHON_SHORT_VERSION}\python.exe'" '"$@"' > /usr/bin/python \
    && echo "wine 'C:\Python${PYTHON_SHORT_VERSION}\Scripts\easy_install.exe'" '"$@"' > /usr/bin/easy_install \
    && echo "wine 'C:\Python${PYTHON_SHORT_VERSION}\Scripts\pip.exe'" '"$@"' > /usr/bin/pip \
    && echo "wine 'C:\Python${PYTHON_SHORT_VERSION}\Scripts\pyinstaller.exe'" '"$@"' > /usr/bin/pyinstaller \
    && echo "wine 'C:\Python${PYTHON_SHORT_VERSION}\Scripts\pyupdater.exe'" '"$@"' > /usr/bin/pyupdater \
    && echo 'assoc .py=PythonScript' | wine cmd \
    && echo "ftype PythonScript=c:\Python${PYTHON_SHORT_VERSION}\python.exe" '"%1" %*' | wine cmd \
    && while pgrep wineserver >/dev/null; do echo "Waiting for wineserver"; sleep 1; done \
    && chmod +x /usr/bin/python /usr/bin/easy_install /usr/bin/pip /usr/bin/pyinstaller /usr/bin/pyupdater \
    && (pip install -U pip || true) \
    && rm -rf /tmp/.wine-*

ENV W_DRIVE_C=/wine/drive_c
ENV W_WINDIR_UNIX="$W_DRIVE_C/windows"
ENV W_SYSTEM64_DLLS="$W_WINDIR_UNIX/system32"
ENV W_TMP="$W_DRIVE_C/windows/temp/_$0"

# install Microsoft Visual C++ Redistributable for Visual Studio 2017 dll files
RUN set -x \
    && rm -f "$W_TMP"/* \
    && wget -P "$W_TMP" https://download.visualstudio.microsoft.com/download/pr/11100230/15ccb3f02745c7b206ad10373cbca89b/VC_redist.x64.exe \
    && cabextract -q --directory="$W_TMP" "$W_TMP"/VC_redist.x64.exe \
    && cabextract -q --directory="$W_TMP" "$W_TMP/a10" \
    && cabextract -q --directory="$W_TMP" "$W_TMP/a11" \
    && cd "$W_TMP" \
    && rename 's/_/\-/g' *.dll \
    && cp "$W_TMP"/*.dll "$W_SYSTEM64_DLLS"/

# install pyinstaller
RUN /usr/bin/pip install pyinstaller==$PYINSTALLER_VERSION

# Install git, sadly needs xvfb, also hangs, please forgive me...
RUN \
    apt-get install -y --no-install-recommends xvfb && \
    git_installer="Git-${GIT_VERSION}-64-bit.exe" && \
    wget "https://github.com/git-for-windows/git/releases/download/v${GIT_VERSION}.windows.1/${git_installer}" && \
    xvfb-run wine "${git_installer}" \
        /VERYSILENT \
        /NORESTART \
        /NOCANCEL \
        /SP- \
        /CLOSEAPPLICATIONS \
        /RESTARTAPPLICATIONS \
        /COMPONENTS="" \
    & \
    ( \
        while ! grep Git "${WINEPREFIX}/system.reg" | grep PATH >/dev/null; do \
            sleep 1; \
        done && \
        wineserver -k \
    ); \
    rm -f "${git_installer}"

# put the src folder inside wine
RUN mkdir /src/ && ln -s /src /wine/drive_c/src
VOLUME /src/
WORKDIR /wine/drive_c/src/
RUN mkdir -p /wine/drive_c/tmp

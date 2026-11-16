sudo apt update -y
sudo apt upgrade -y
sudo apt install -y build-essential
sudo apt install -y gcc-13 g++-13 cpp-13
#sudo apt install -y cmake
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-13 100 --slave /usr/bin/g++ g++ /usr/bin/g++-13 --slave /usr/bin/gcov gcov /usr/bin/gcov-13
sudo update-alternatives --config gcc # chose gcc-13
sudo apt install -y libsctp-dev cmake-curses-gui libpcre2-dev curl git
git clone https://gitlab.eurecom.fr/mosaic5g/flexric flexric
cd flexric/
git checkout f1c08ed2b9b1eceeda7941dd7bf435db0168dd56
mkdir build && cd build && cmake -DXAPP_MULTILANGUAGE=OFF .. && make -j8
sudo make install
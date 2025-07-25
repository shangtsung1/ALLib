dub build --config=cwrapper --compiler=ldc2
dub build
cp liballib.so examp/C/
cd examp/C
gcc -o main main.c -I../../source/allib -L. -lallib -ldruntime-ldc-shared

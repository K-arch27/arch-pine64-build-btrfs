# arch-pine64-build-btrfs
Rootfs builder for Arch Linux ARM on PinePhone (Pro)/PineTab

Work in progress to try and make it generate Image on a Btrfs Root with a snapper compatible layout for rollback


Usage example : sudo ./build -a aarch64 -d pinephone-pro -u ui phosh
other parameters are optionnal

         [-a architecture] architecture = aarch64 or armv7

         [-d device] device = pinephone pinephone-pro pinetab
         
         [-u ui] ui = barebone phosh plasma sxmo
         
         [-h hostname] 
         
         [--username username]
         
         [--osk-sdl] 0 or 1
         
         [--noconfirm] 0 or 1
         
         [--cachedir directory]
         
         [--no-cachedir]

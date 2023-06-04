# arch-pine64-build-btrfs
Rootfs builder for Arch Linux ARM on PinePhone (Pro)/PineTab

generate Image on a Btrfs Root with a snapper compatible layout for rollback

(An ARM environement is required since this script chroot inside the generated system)

Default User/Pass : alarm/123456

--

Usage :

         req.  [-a architecture] architecture = aarch64 or armv7

         req.  [-d device] device = pinephone pinephone-pro pinetab
         
         req.  [-u ui] ui = barebone phosh plasma sxmo
         
         [-h hostname] 
         
         [--username username]
         
         [--password password]
         
         [--osk-sdl] 0 or 1
         
         [--noconfirm] 0 or 1
         
         [--cachedir directory]
         
         [--no-cachedir]

Example : sudo ./build -a aarch64 -d pinephone-pro -u ui phosh

Example with custom Info: sudo ./build -a aarch64 -d pinephone-pro -u ui phosh -h Pine-Arch-Btrfs --username kaida --password 1234

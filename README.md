# arch-pine64-build-btrfs


         
Rootfs builder for Arch Linux ARM on PinePhone (Pro)/PineTab(2)

(only tested with Pinephone Pro as I don't own the OG or the PineTab/2)

generate Image on a Btrfs Root with snapper for Snapshot/rollback

<img src="https://github.com/K-arch27/arch-pine64-build-btrfs/assets/98610690/fa6daaaf-e13f-4a58-be93-5a1a5d356d54">


Default User/Pass : alarm/123456

         
## Usage :

         req.  [-a architecture] architecture = aarch64 or armv7

         req.  [-d device] device = pinephone pinephone-pro pinetab
         
         req.  [-u ui] ui = barebone phosh plasma sxmo
         
         [-h hostname] 
         
         [--username username]
         
         [--password password]
         
         [--osk-sdl]
         
         [--noconfirm]
         
         [--cachedir directory] directory = directory path for the pkgcache
         
         [--no-cachedir]

Example : sudo ./build -a aarch64 -d pinephone-pro -u ui phosh

Example with custom Info: sudo ./build -a aarch64 -d pinephone-pro -u ui phosh -h Pine-Arch-Btrfs --username kaida --password 1234




## Building on x86\_64

If you want to cross-build the image from another architecture, you will need to [use QEMU](https://wiki.archlinux.org/title/QEMU#Chrooting_into_arm/arm64_environment_from_x86_64) for the second build stage.

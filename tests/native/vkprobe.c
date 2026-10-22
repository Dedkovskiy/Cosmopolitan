// Build: clang -arch x86_64 -I <Vulkan-Headers>/include vkprobe.c -o vkprobe; run: VK_DRIVER_FILES=<engine>/MoltenVK_icd.json ./vkprobe <engine>/lib/wine/x86_64-unix/libvulkan.1.dylib
// Asks the engine's own Vulkan loader + MoltenVK which features DXVK and vkd3d-proton need are supported (run with VK_DRIVER_FILES).
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan_core.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    void *lib = dlopen(argv[1], RTLD_NOW); if (!lib) { printf("dlopen failed: %s\n", dlerror()); return 1; }
    PFN_vkGetInstanceProcAddr gipa = (PFN_vkGetInstanceProcAddr)dlsym(lib, "vkGetInstanceProcAddr");
    PFN_vkCreateInstance ci = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
    VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO, NULL, "probe", 1, "probe", 1, VK_API_VERSION_1_3 };
    VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, NULL, 0, &app, 0, NULL, 0, NULL };
    VkInstance inst; VkResult r = ci(&ici, NULL, &inst); if (r) { printf("vkCreateInstance %d\n", r); return 1; }
    PFN_vkEnumeratePhysicalDevices epd = (PFN_vkEnumeratePhysicalDevices)gipa(inst, "vkEnumeratePhysicalDevices");
    PFN_vkGetPhysicalDeviceProperties gpp = (PFN_vkGetPhysicalDeviceProperties)gipa(inst, "vkGetPhysicalDeviceProperties");
    PFN_vkGetPhysicalDeviceFeatures2 gpf2 = (PFN_vkGetPhysicalDeviceFeatures2)gipa(inst, "vkGetPhysicalDeviceFeatures2");
    PFN_vkEnumerateDeviceExtensionProperties edep = (PFN_vkEnumerateDeviceExtensionProperties)gipa(inst, "vkEnumerateDeviceExtensionProperties");
    uint32_t n = 1; VkPhysicalDevice pd; epd(inst, &n, &pd); if (!n) { printf("no device\n"); return 1; }
    VkPhysicalDeviceProperties p; gpp(pd, &p);
    printf("device: %s, driver version raw %u, API %u.%u.%u\n", p.deviceName, p.driverVersion, VK_API_VERSION_MAJOR(p.apiVersion), VK_API_VERSION_MINOR(p.apiVersion), VK_API_VERSION_PATCH(p.apiVersion));
    VkPhysicalDeviceTransformFeedbackFeaturesEXT tf = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TRANSFORM_FEEDBACK_FEATURES_EXT };
    VkPhysicalDeviceRobustness2FeaturesEXT rb = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT, &tf };
    VkPhysicalDeviceFeatures2 f = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, &rb };
    gpf2(pd, &f);
    printf("geometryShader=%u shaderCullDistance=%u shaderClipDistance=%u robustBufferAccess2=%u robustImageAccess2=%u nullDescriptor=%u transformFeedback=%u\n",
        f.features.geometryShader, f.features.shaderCullDistance, f.features.shaderClipDistance, rb.robustBufferAccess2, rb.robustImageAccess2, rb.nullDescriptor, tf.transformFeedback);
    uint32_t ne = 0; edep(pd, NULL, &ne, NULL); VkExtensionProperties e[512]; if (ne > 512) ne = 512; edep(pd, NULL, &ne, e);
    const char *want[] = { "VK_EXT_robustness2", "VK_EXT_transform_feedback", "VK_KHR_maintenance5", "VK_KHR_maintenance6", "VK_EXT_mutable_descriptor_type", "VK_EXT_descriptor_buffer" };
    for (int i = 0; i < 6; i++) { int has = 0; for (uint32_t j = 0; j < ne; j++) if (!strcmp(e[j].extensionName, want[i])) has = 1; printf("%s=%s ", want[i], has ? "yes" : "no"); }
    printf("\n(%u device extensions)\n", ne);
    return 0;
}

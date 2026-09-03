/**
 * @file render_vulkan.cpp
 *
 * Native Vulkan 2D/32-bit Presentation Engine for DevilutionX.
 */
#include "engine/render_vulkan/render_vulkan.hpp"

#include <SDL.h>
#include <SDL_vulkan.h>
#include <vulkan/vulkan.h>

#include <algorithm>
#include <cstring>
#include <vector>

#include "utils/log.hpp"
#include "engine/dx.h"
#include "engine/render/scrollrt.h"
#include "engine/render_bridge.hpp"
#include "control.h"

namespace devilution {

bool gbVulkanRequested = false;
float g_SmoothZoomFactor = 1.0f;

namespace {

struct PushConstantBlock {
	int32_t shaderStyle;
	float screenWidth;
	float screenHeight;
	float time;
	float zoomFactor;
	int32_t colorProfile;
	int32_t atmosphereFx;
	float mainPanelX;
	float mainPanelY;
	float mainPanelW;
	float mainPanelH;
	int32_t leftPanelOpen;
	int32_t rightPanelOpen;
};

bool g_VulkanActive = false;
SDL_Window *g_Window = nullptr;
int g_BufferWidth = 0;
int g_BufferHeight = 0;

VkInstance g_Instance = VK_NULL_HANDLE;
VkSurfaceKHR g_Surface = VK_NULL_HANDLE;
VkPhysicalDevice g_PhysicalDevice = VK_NULL_HANDLE;
VkDevice g_Device = VK_NULL_HANDLE;
uint32_t g_QueueFamilyIndex = 0;
VkQueue g_Queue = VK_NULL_HANDLE;

VkSwapchainKHR g_Swapchain = VK_NULL_HANDLE;
VkFormat g_SwapchainFormat = VK_FORMAT_B8G8R8A8_UNORM;
VkExtent2D g_SwapchainExtent = { 0, 0 };
std::vector<VkImage> g_SwapchainImages;
std::vector<VkImageView> g_SwapchainImageViews;
std::vector<VkFramebuffer> g_Framebuffers;

VkRenderPass g_RenderPass = VK_NULL_HANDLE;
VkDescriptorSetLayout g_DescriptorSetLayout = VK_NULL_HANDLE;
VkDescriptorPool g_DescriptorPool = VK_NULL_HANDLE;
VkDescriptorSet g_DescriptorSet = VK_NULL_HANDLE;
VkPipelineLayout g_PipelineLayout = VK_NULL_HANDLE;
VkPipeline g_Pipeline = VK_NULL_HANDLE;
VkCommandPool g_CommandPool = VK_NULL_HANDLE;
std::vector<VkCommandBuffer> g_CommandBuffers;

// Texture and staging buffer
VkImage g_TextureImage = VK_NULL_HANDLE;
VkDeviceMemory g_TextureMemory = VK_NULL_HANDLE;
VkImageView g_TextureView = VK_NULL_HANDLE;
VkSampler g_Sampler = VK_NULL_HANDLE;

VkBuffer g_StagingBuffer = VK_NULL_HANDLE;
VkDeviceMemory g_StagingMemory = VK_NULL_HANDLE;
void *g_StagingMapped = nullptr;

// Synchronization
static const int MAX_FRAMES_IN_FLIGHT = 2;
VkSemaphore g_ImageAvailableSemaphores[MAX_FRAMES_IN_FLIGHT];
VkSemaphore g_RenderFinishedSemaphores[MAX_FRAMES_IN_FLIGHT];
VkFence g_InFlightFences[MAX_FRAMES_IN_FLIGHT];
size_t g_CurrentFrame = 0;

#include "engine/render_vulkan/shaders_spirv.hpp"

uint32_t FindMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties)
{
	VkPhysicalDeviceMemoryProperties memProperties;
	vkGetPhysicalDeviceMemoryProperties(g_PhysicalDevice, &memProperties);

	for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
		if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
			return i;
		}
	}
	return 0;
}

VkShaderModule CreateShaderModule(const uint32_t *code, size_t sizeBytes)
{
	VkShaderModuleCreateInfo createInfo {};
	createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
	createInfo.codeSize = sizeBytes;
	createInfo.pCode = code;

	VkShaderModule shaderModule;
	if (vkCreateShaderModule(g_Device, &createInfo, nullptr, &shaderModule) != VK_SUCCESS) {
		return VK_NULL_HANDLE;
	}
	return shaderModule;
}

} // namespace

bool Vulkan_IsActive()
{
	return g_VulkanActive;
}

bool Vulkan_Init(SDL_Window *window, int width, int height)
{
	if (SDL_Vulkan_LoadLibrary(nullptr) != 0) {
		Log("Vulkan: Failed to load Vulkan library: {}", SDL_GetError());
		return false;
	}

	g_Window = window;
	g_BufferWidth = width;
	g_BufferHeight = height;

	// 1. Instance Creation
	unsigned int extCount = 0;
	if (!SDL_Vulkan_GetInstanceExtensions(window, &extCount, nullptr)) {
		Log("Vulkan: Failed to get extension count: {}", SDL_GetError());
		return false;
	}

	std::vector<const char *> extensions(extCount);
	SDL_Vulkan_GetInstanceExtensions(window, &extCount, extensions.data());

	VkApplicationInfo appInfo {};
	appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
	appInfo.pApplicationName = "DevilutionX HD Resurrected";
	appInfo.applicationVersion = VK_MAKE_VERSION(1, 5, 5);
	appInfo.pEngineName = "D1R Vulkan Engine";
	appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
	appInfo.apiVersion = VK_API_VERSION_1_0;

	VkInstanceCreateInfo instInfo {};
	instInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
	instInfo.pApplicationInfo = &appInfo;
	instInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
	instInfo.ppEnabledExtensionNames = extensions.data();

	if (vkCreateInstance(&instInfo, nullptr, &g_Instance) != VK_SUCCESS) {
		Log("Vulkan: Failed to create VkInstance");
		return false;
	}

	// 2. Surface Creation
	if (!SDL_Vulkan_CreateSurface(window, g_Instance, &g_Surface)) {
		Log("Vulkan: Failed to create SDL surface: {}", SDL_GetError());
		Vulkan_Cleanup();
		return false;
	}

	// 3. Physical Device Selection
	uint32_t deviceCount = 0;
	vkEnumeratePhysicalDevices(g_Instance, &deviceCount, nullptr);
	if (deviceCount == 0) {
		Log("Vulkan: No Vulkan physical devices found");
		Vulkan_Cleanup();
		return false;
	}

	std::vector<VkPhysicalDevice> devices(deviceCount);
	vkEnumeratePhysicalDevices(g_Instance, &deviceCount, devices.data());

	for (const auto &device : devices) {
		VkPhysicalDeviceProperties props;
		vkGetPhysicalDeviceProperties(device, &props);
		if (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
			g_PhysicalDevice = device;
			Log("Vulkan: Selected Discrete GPU: {}", props.deviceName);
			break;
		}
	}
	if (g_PhysicalDevice == VK_NULL_HANDLE) {
		g_PhysicalDevice = devices[0];
		VkPhysicalDeviceProperties props;
		vkGetPhysicalDeviceProperties(g_PhysicalDevice, &props);
		Log("Vulkan: Selected GPU: {}", props.deviceName);
	}

	// 4. Queue Family
	uint32_t queueFamilyCount = 0;
	vkGetPhysicalDeviceQueueFamilyProperties(g_PhysicalDevice, &queueFamilyCount, nullptr);
	std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
	vkGetPhysicalDeviceQueueFamilyProperties(g_PhysicalDevice, &queueFamilyCount, queueFamilies.data());

	bool queueFound = false;
	for (uint32_t i = 0; i < queueFamilyCount; i++) {
		VkBool32 presentSupport = false;
		vkGetPhysicalDeviceSurfaceSupportKHR(g_PhysicalDevice, i, g_Surface, &presentSupport);
		if ((queueFamilies[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && presentSupport) {
			g_QueueFamilyIndex = i;
			queueFound = true;
			break;
		}
	}
	if (!queueFound) {
		Log("Vulkan: Suitable queue family not found");
		Vulkan_Cleanup();
		return false;
	}

	// 5. Logical Device
	float queuePriority = 1.0f;
	VkDeviceQueueCreateInfo queueCreateInfo {};
	queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
	queueCreateInfo.queueFamilyIndex = g_QueueFamilyIndex;
	queueCreateInfo.queueCount = 1;
	queueCreateInfo.pQueuePriorities = &queuePriority;

	const char *deviceExtensions[] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
	VkDeviceCreateInfo deviceCreateInfo {};
	deviceCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
	deviceCreateInfo.pQueueCreateInfos = &queueCreateInfo;
	deviceCreateInfo.queueCreateInfoCount = 1;
	deviceCreateInfo.enabledExtensionCount = 1;
	deviceCreateInfo.ppEnabledExtensionNames = deviceExtensions;

	if (vkCreateDevice(g_PhysicalDevice, &deviceCreateInfo, nullptr, &g_Device) != VK_SUCCESS) {
		Log("Vulkan: Failed to create logical device");
		Vulkan_Cleanup();
		return false;
	}
	vkGetDeviceQueue(g_Device, g_QueueFamilyIndex, 0, &g_Queue);

	// 6. Swapchain Creation
	VkSurfaceCapabilitiesKHR capabilities;
	vkGetPhysicalDeviceSurfaceCapabilitiesKHR(g_PhysicalDevice, g_Surface, &capabilities);

	int winW = 0, winH = 0;
	SDL_Vulkan_GetDrawableSize(window, &winW, &winH);
	if (winW <= 0 || winH <= 0) {
		winW = width > 0 ? width : 2560;
		winH = height > 0 ? height : 1440;
	}
	g_SwapchainExtent = { static_cast<uint32_t>(winW), static_cast<uint32_t>(winH) };
	if (capabilities.currentExtent.width != UINT32_MAX && capabilities.currentExtent.width > 0) {
		g_SwapchainExtent = capabilities.currentExtent;
	}

	uint32_t formatCount = 0;
	vkGetPhysicalDeviceSurfaceFormatsKHR(g_PhysicalDevice, g_Surface, &formatCount, nullptr);
	if (formatCount > 0) {
		std::vector<VkSurfaceFormatKHR> formats(formatCount);
		vkGetPhysicalDeviceSurfaceFormatsKHR(g_PhysicalDevice, g_Surface, &formatCount, formats.data());
		g_SwapchainFormat = formats[0].format;
		for (const auto &fmt : formats) {
			if (fmt.format == VK_FORMAT_B8G8R8A8_UNORM || fmt.format == VK_FORMAT_R8G8B8A8_UNORM) {
				g_SwapchainFormat = fmt.format;
				break;
			}
		}
	}

	uint32_t imageCount = capabilities.minImageCount + 1;
	if (capabilities.maxImageCount > 0 && imageCount > capabilities.maxImageCount) {
		imageCount = capabilities.maxImageCount;
	}

	VkCompositeAlphaFlagBitsKHR compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
	if (!(capabilities.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR)) {
		if (capabilities.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR)
			compositeAlpha = VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR;
		else if (capabilities.supportedCompositeAlpha & VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR)
			compositeAlpha = VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR;
	}

	VkSwapchainCreateInfoKHR swapchainInfo {};
	swapchainInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
	swapchainInfo.surface = g_Surface;
	swapchainInfo.minImageCount = imageCount;
	swapchainInfo.imageFormat = g_SwapchainFormat;
	swapchainInfo.imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
	swapchainInfo.imageExtent = g_SwapchainExtent;
	swapchainInfo.imageArrayLayers = 1;
	swapchainInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
	swapchainInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
	swapchainInfo.preTransform = capabilities.currentTransform;
	swapchainInfo.compositeAlpha = compositeAlpha;
	swapchainInfo.presentMode = VK_PRESENT_MODE_FIFO_KHR; // VSync / Triple Buffer
	swapchainInfo.clipped = VK_TRUE;

	if (vkCreateSwapchainKHR(g_Device, &swapchainInfo, nullptr, &g_Swapchain) != VK_SUCCESS) {
		Log("Vulkan: Failed to create swapchain");
		Vulkan_Cleanup();
		return false;
	}

	uint32_t scImgCount = 0;
	vkGetSwapchainImagesKHR(g_Device, g_Swapchain, &scImgCount, nullptr);
	g_SwapchainImages.resize(scImgCount);
	vkGetSwapchainImagesKHR(g_Device, g_Swapchain, &scImgCount, g_SwapchainImages.data());

	g_SwapchainImageViews.resize(scImgCount);
	for (size_t i = 0; i < scImgCount; i++) {
		VkImageViewCreateInfo viewInfo {};
		viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
		viewInfo.image = g_SwapchainImages[i];
		viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
		viewInfo.format = g_SwapchainFormat;
		viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
		viewInfo.subresourceRange.levelCount = 1;
		viewInfo.subresourceRange.layerCount = 1;
		vkCreateImageView(g_Device, &viewInfo, nullptr, &g_SwapchainImageViews[i]);
	}

	// 7. RenderPass
	VkAttachmentDescription colorAttachment {};
	colorAttachment.format = g_SwapchainFormat;
	colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
	colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
	colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
	colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
	colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

	VkAttachmentReference colorAttachmentRef {};
	colorAttachmentRef.attachment = 0;
	colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

	VkSubpassDescription subpass {};
	subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
	subpass.colorAttachmentCount = 1;
	subpass.pColorAttachments = &colorAttachmentRef;

	VkRenderPassCreateInfo renderPassInfo {};
	renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
	renderPassInfo.attachmentCount = 1;
	renderPassInfo.pAttachments = &colorAttachment;
	renderPassInfo.subpassCount = 1;
	renderPassInfo.pSubpasses = &subpass;

	vkCreateRenderPass(g_Device, &renderPassInfo, nullptr, &g_RenderPass);

	// 8. Framebuffers
	g_Framebuffers.resize(g_SwapchainImageViews.size());
	for (size_t i = 0; i < g_SwapchainImageViews.size(); i++) {
		VkImageView attachments[] = { g_SwapchainImageViews[i] };
		VkFramebufferCreateInfo fbInfo {};
		fbInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
		fbInfo.renderPass = g_RenderPass;
		fbInfo.attachmentCount = 1;
		fbInfo.pAttachments = attachments;
		fbInfo.width = g_SwapchainExtent.width;
		fbInfo.height = g_SwapchainExtent.height;
		fbInfo.layers = 1;
		vkCreateFramebuffer(g_Device, &fbInfo, nullptr, &g_Framebuffers[i]);
	}

	// 9. Command Pool
	VkCommandPoolCreateInfo poolInfo {};
	poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
	poolInfo.queueFamilyIndex = g_QueueFamilyIndex;
	poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
	vkCreateCommandPool(g_Device, &poolInfo, nullptr, &g_CommandPool);

	// 10. Texture & Staging Buffer
	VkDeviceSize imageSize = static_cast<VkDeviceSize>(width * height * 4);

	VkBufferCreateInfo stagingBufferInfo {};
	stagingBufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
	stagingBufferInfo.size = imageSize;
	stagingBufferInfo.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
	stagingBufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
	vkCreateBuffer(g_Device, &stagingBufferInfo, nullptr, &g_StagingBuffer);

	VkMemoryRequirements stagingMemReq;
	vkGetBufferMemoryRequirements(g_Device, g_StagingBuffer, &stagingMemReq);

	VkMemoryAllocateInfo stagingAllocInfo {};
	stagingAllocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
	stagingAllocInfo.allocationSize = stagingMemReq.size;
	stagingAllocInfo.memoryTypeIndex = FindMemoryType(stagingMemReq.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
	vkAllocateMemory(g_Device, &stagingAllocInfo, nullptr, &g_StagingMemory);
	vkBindBufferMemory(g_Device, g_StagingBuffer, g_StagingMemory, 0);
	vkMapMemory(g_Device, g_StagingMemory, 0, imageSize, 0, &g_StagingMapped);

	// Texture Image
	VkImageCreateInfo texImageInfo {};
	texImageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
	texImageInfo.imageType = VK_IMAGE_TYPE_2D;
	texImageInfo.extent.width = static_cast<uint32_t>(width);
	texImageInfo.extent.height = static_cast<uint32_t>(height);
	texImageInfo.extent.depth = 1;
	texImageInfo.mipLevels = 1;
	texImageInfo.arrayLayers = 1;
	texImageInfo.format = VK_FORMAT_B8G8R8A8_UNORM;
	texImageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
	texImageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
	texImageInfo.usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
	texImageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
	texImageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
	vkCreateImage(g_Device, &texImageInfo, nullptr, &g_TextureImage);

	VkMemoryRequirements texMemReq;
	vkGetImageMemoryRequirements(g_Device, g_TextureImage, &texMemReq);
	VkMemoryAllocateInfo texAllocInfo {};
	texAllocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
	texAllocInfo.allocationSize = texMemReq.size;
	texAllocInfo.memoryTypeIndex = FindMemoryType(texMemReq.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
	vkAllocateMemory(g_Device, &texAllocInfo, nullptr, &g_TextureMemory);
	vkBindImageMemory(g_Device, g_TextureImage, g_TextureMemory, 0);

	// Texture View & Sampler
	VkImageViewCreateInfo texViewInfo {};
	texViewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
	texViewInfo.image = g_TextureImage;
	texViewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
	texViewInfo.format = VK_FORMAT_B8G8R8A8_UNORM;
	texViewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	texViewInfo.subresourceRange.levelCount = 1;
	texViewInfo.subresourceRange.layerCount = 1;
	vkCreateImageView(g_Device, &texViewInfo, nullptr, &g_TextureView);

	VkSamplerCreateInfo samplerInfo {};
	samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
	samplerInfo.magFilter = VK_FILTER_NEAREST;
	samplerInfo.minFilter = VK_FILTER_NEAREST;
	samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
	samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
	samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
	vkCreateSampler(g_Device, &samplerInfo, nullptr, &g_Sampler);

	// 11. Descriptor Pool & Set
	VkDescriptorSetLayoutBinding samplerBinding {};
	samplerBinding.binding = 0;
	samplerBinding.descriptorCount = 1;
	samplerBinding.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
	samplerBinding.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;

	VkDescriptorSetLayoutCreateInfo layoutInfo {};
	layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
	layoutInfo.bindingCount = 1;
	layoutInfo.pBindings = &samplerBinding;
	vkCreateDescriptorSetLayout(g_Device, &layoutInfo, nullptr, &g_DescriptorSetLayout);

	VkDescriptorPoolSize poolSize {};
	poolSize.type = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
	poolSize.descriptorCount = 1;

	VkDescriptorPoolCreateInfo descPoolInfo {};
	descPoolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
	descPoolInfo.poolSizeCount = 1;
	descPoolInfo.pPoolSizes = &poolSize;
	descPoolInfo.maxSets = 1;
	vkCreateDescriptorPool(g_Device, &descPoolInfo, nullptr, &g_DescriptorPool);

	VkDescriptorSetAllocateInfo descAllocInfo {};
	descAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
	descAllocInfo.descriptorPool = g_DescriptorPool;
	descAllocInfo.descriptorSetCount = 1;
	descAllocInfo.pSetLayouts = &g_DescriptorSetLayout;
	vkAllocateDescriptorSets(g_Device, &descAllocInfo, &g_DescriptorSet);

	VkDescriptorImageInfo descImageInfo {};
	descImageInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
	descImageInfo.imageView = g_TextureView;
	descImageInfo.sampler = g_Sampler;

	VkWriteDescriptorSet descriptorWrite {};
	descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
	descriptorWrite.dstSet = g_DescriptorSet;
	descriptorWrite.dstBinding = 0;
	descriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
	descriptorWrite.descriptorCount = 1;
	descriptorWrite.pImageInfo = &descImageInfo;
	vkUpdateDescriptorSets(g_Device, 1, &descriptorWrite, 0, nullptr);

	// 12. Graphics Pipeline
	VkShaderModule vertShader = CreateShaderModule(g_VertSpirv, sizeof(g_VertSpirv));
	VkShaderModule fragShader = CreateShaderModule(g_FragSpirv, sizeof(g_FragSpirv));

	VkPipelineShaderStageCreateInfo shaderStages[2] {};
	shaderStages[0].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
	shaderStages[0].stage = VK_SHADER_STAGE_VERTEX_BIT;
	shaderStages[0].module = vertShader;
	shaderStages[0].pName = "main";

	shaderStages[1].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
	shaderStages[1].stage = VK_SHADER_STAGE_FRAGMENT_BIT;
	shaderStages[1].module = fragShader;
	shaderStages[1].pName = "main";

	VkPipelineVertexInputStateCreateInfo vertexInputInfo {};
	vertexInputInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

	VkPipelineInputAssemblyStateCreateInfo inputAssembly {};
	inputAssembly.sType = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
	inputAssembly.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

	VkViewport viewport { 0.0f, 0.0f, static_cast<float>(g_SwapchainExtent.width), static_cast<float>(g_SwapchainExtent.height), 0.0f, 1.0f };
	VkRect2D scissor { { 0, 0 }, g_SwapchainExtent };
	VkPipelineViewportStateCreateInfo viewportState {};
	viewportState.sType = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
	viewportState.viewportCount = 1;
	viewportState.pViewports = &viewport;
	viewportState.scissorCount = 1;
	viewportState.pScissors = &scissor;

	VkPipelineRasterizationStateCreateInfo rasterizer {};
	rasterizer.sType = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
	rasterizer.cullMode = VK_CULL_MODE_NONE;
	rasterizer.frontFace = VK_FRONT_FACE_CLOCKWISE;
	rasterizer.lineWidth = 1.0f;

	VkPipelineMultisampleStateCreateInfo multisampling {};
	multisampling.sType = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
	multisampling.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

	VkPipelineColorBlendAttachmentState colorBlendAttachment {};
	colorBlendAttachment.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT | VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
	colorBlendAttachment.blendEnable = VK_FALSE;

	VkPipelineColorBlendStateCreateInfo colorBlending {};
	colorBlending.sType = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
	colorBlending.attachmentCount = 1;
	colorBlending.pAttachments = &colorBlendAttachment;

	VkPushConstantRange pushRange {};
	pushRange.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
	pushRange.offset = 0;
	pushRange.size = sizeof(PushConstantBlock);

	VkPipelineLayoutCreateInfo pipelineLayoutInfo {};
	pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
	pipelineLayoutInfo.setLayoutCount = 1;
	pipelineLayoutInfo.pSetLayouts = &g_DescriptorSetLayout;
	pipelineLayoutInfo.pushConstantRangeCount = 1;
	pipelineLayoutInfo.pPushConstantRanges = &pushRange;
	vkCreatePipelineLayout(g_Device, &pipelineLayoutInfo, nullptr, &g_PipelineLayout);

	VkGraphicsPipelineCreateInfo pipelineInfo {};
	pipelineInfo.sType = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
	pipelineInfo.stageCount = 2;
	pipelineInfo.pStages = shaderStages;
	pipelineInfo.pVertexInputState = &vertexInputInfo;
	pipelineInfo.pInputAssemblyState = &inputAssembly;
	pipelineInfo.pViewportState = &viewportState;
	pipelineInfo.pRasterizationState = &rasterizer;
	pipelineInfo.pMultisampleState = &multisampling;
	pipelineInfo.pColorBlendState = &colorBlending;
	pipelineInfo.layout = g_PipelineLayout;
	pipelineInfo.renderPass = g_RenderPass;
	pipelineInfo.subpass = 0;

	vkCreateGraphicsPipelines(g_Device, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &g_Pipeline);

	vkDestroyShaderModule(g_Device, vertShader, nullptr);
	vkDestroyShaderModule(g_Device, fragShader, nullptr);

	// 13. Command Buffers & Sync
	g_CommandBuffers.resize(MAX_FRAMES_IN_FLIGHT);
	VkCommandBufferAllocateInfo cmdAllocInfo {};
	cmdAllocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
	cmdAllocInfo.commandPool = g_CommandPool;
	cmdAllocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
	cmdAllocInfo.commandBufferCount = MAX_FRAMES_IN_FLIGHT;
	vkAllocateCommandBuffers(g_Device, &cmdAllocInfo, g_CommandBuffers.data());

	VkSemaphoreCreateInfo semInfo {};
	semInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

	VkFenceCreateInfo fenceInfo {};
	fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
	fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;

	for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
		vkCreateSemaphore(g_Device, &semInfo, nullptr, &g_ImageAvailableSemaphores[i]);
		vkCreateSemaphore(g_Device, &semInfo, nullptr, &g_RenderFinishedSemaphores[i]);
		vkCreateFence(g_Device, &fenceInfo, nullptr, &g_InFlightFences[i]);
	}

	g_VulkanActive = true;
	Log("Vulkan: Native Vulkan 2D Presentation Engine successfully initialized!");
	return true;
}

void Vulkan_Cleanup()
{
	if (g_Device != VK_NULL_HANDLE) {
		vkDeviceWaitIdle(g_Device);

		for (int i = 0; i < MAX_FRAMES_IN_FLIGHT; i++) {
			vkDestroySemaphore(g_Device, g_ImageAvailableSemaphores[i], nullptr);
			vkDestroySemaphore(g_Device, g_RenderFinishedSemaphores[i], nullptr);
			vkDestroyFence(g_Device, g_InFlightFences[i], nullptr);
		}

		if (g_StagingMapped) {
			vkUnmapMemory(g_Device, g_StagingMemory);
			g_StagingMapped = nullptr;
		}
		vkDestroyBuffer(g_Device, g_StagingBuffer, nullptr);
		vkFreeMemory(g_Device, g_StagingMemory, nullptr);

		vkDestroySampler(g_Device, g_Sampler, nullptr);
		vkDestroyImageView(g_Device, g_TextureView, nullptr);
		vkDestroyImage(g_Device, g_TextureImage, nullptr);
		vkFreeMemory(g_Device, g_TextureMemory, nullptr);

		vkDestroyPipeline(g_Device, g_Pipeline, nullptr);
		vkDestroyPipelineLayout(g_Device, g_PipelineLayout, nullptr);
		vkDestroyDescriptorPool(g_Device, g_DescriptorPool, nullptr);
		vkDestroyDescriptorSetLayout(g_Device, g_DescriptorSetLayout, nullptr);

		for (auto fb : g_Framebuffers)
			vkDestroyFramebuffer(g_Device, fb, nullptr);
		g_Framebuffers.clear();

		vkDestroyRenderPass(g_Device, g_RenderPass, nullptr);

		for (auto iv : g_SwapchainImageViews)
			vkDestroyImageView(g_Device, iv, nullptr);
		g_SwapchainImageViews.clear();

		vkDestroySwapchainKHR(g_Device, g_Swapchain, nullptr);
		vkDestroyCommandPool(g_Device, g_CommandPool, nullptr);
		vkDestroyDevice(g_Device, nullptr);
	}

	if (g_Surface != VK_NULL_HANDLE) {
		vkDestroySurfaceKHR(g_Instance, g_Surface, nullptr);
	}

	if (g_Instance != VK_NULL_HANDLE) {
		vkDestroyInstance(g_Instance, nullptr);
	}

	SDL_Vulkan_UnloadLibrary();
	g_VulkanActive = false;
	Log("Vulkan: Subsystem cleaned up.");
}

void Vulkan_RenderPresent(const SDL_Surface *surface)
{
	if (!g_VulkanActive || surface == nullptr || surface->pixels == nullptr)
		return;

	// Copy 32-bit surface to staging buffer
	std::memcpy(g_StagingMapped, surface->pixels, surface->w * surface->h * 4);

	// Export frame to Godot 4 / UE5 Shared Memory Bridge
	ExportGodotFrame(surface);

	vkWaitForFences(g_Device, 1, &g_InFlightFences[g_CurrentFrame], VK_TRUE, UINT64_MAX);
	vkResetFences(g_Device, 1, &g_InFlightFences[g_CurrentFrame]);

	uint32_t imageIndex = 0;
	VkResult res = vkAcquireNextImageKHR(g_Device, g_Swapchain, UINT64_MAX, g_ImageAvailableSemaphores[g_CurrentFrame], VK_NULL_HANDLE, &imageIndex);
	if (res != VK_SUCCESS && res != VK_SUBOPTIMAL_KHR)
		return;

	VkCommandBuffer cmd = g_CommandBuffers[g_CurrentFrame];
	vkResetCommandBuffer(cmd, 0);

	VkCommandBufferBeginInfo beginInfo {};
	beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
	vkBeginCommandBuffer(cmd, &beginInfo);

	// 1. Transition Image for Transfer
	VkImageMemoryBarrier barrier1 {};
	barrier1.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
	barrier1.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
	barrier1.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
	barrier1.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	barrier1.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
	barrier1.image = g_TextureImage;
	barrier1.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	barrier1.subresourceRange.levelCount = 1;
	barrier1.subresourceRange.layerCount = 1;
	barrier1.srcAccessMask = 0;
	barrier1.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
	vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier1);

	// 2. Copy Buffer to Image
	VkBufferImageCopy region {};
	region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
	region.imageSubresource.layerCount = 1;
	region.imageExtent = { static_cast<uint32_t>(surface->w), static_cast<uint32_t>(surface->h), 1 };
	vkCmdCopyBufferToImage(cmd, g_StagingBuffer, g_TextureImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

	// 3. Transition Image for Shader Read
	VkImageMemoryBarrier barrier2 = barrier1;
	barrier2.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
	barrier2.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
	barrier2.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
	barrier2.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
	vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier2);

	// 4. RenderPass
	VkRenderPassBeginInfo renderPassInfo {};
	renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
	renderPassInfo.renderPass = g_RenderPass;
	renderPassInfo.framebuffer = g_Framebuffers[imageIndex];
	renderPassInfo.renderArea.offset = { 0, 0 };
	renderPassInfo.renderArea.extent = g_SwapchainExtent;

	VkClearValue clearColor = { { { 0.0f, 0.0f, 0.0f, 1.0f } } };
	renderPassInfo.clearValueCount = 1;
	renderPassInfo.pClearValues = &clearColor;

	vkCmdBeginRenderPass(cmd, &renderPassInfo, VK_SUBPASS_CONTENTS_INLINE);
	vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, g_Pipeline);
	vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, g_PipelineLayout, 0, 1, &g_DescriptorSet, 0, nullptr);

	PushConstantBlock push {};
	push.shaderStyle = static_cast<int32_t>(CurrentShaderStyle);
	push.screenWidth = static_cast<float>(g_SwapchainExtent.width);
	push.screenHeight = static_cast<float>(g_SwapchainExtent.height);
	push.time = static_cast<float>(SDL_GetTicks()) / 1000.0f;
	push.zoomFactor = (CurrentZoomMode == ZoomMode::Zoomed_2x) ? 2.0f : (CurrentZoomMode == ZoomMode::Balanced_1_5x ? 1.5f : 1.0f);
	push.colorProfile = static_cast<int32_t>(CurrentColorProfile);
	push.atmosphereFx = static_cast<int32_t>(CurrentAtmosphereFx);

	const Rectangle &mp = GetMainPanel();
	push.mainPanelX = static_cast<float>(mp.position.x);
	push.mainPanelY = static_cast<float>(mp.position.y);
	push.mainPanelW = static_cast<float>(mp.size.width);
	push.mainPanelH = static_cast<float>(mp.size.height);
	push.leftPanelOpen = IsLeftPanelOpen() ? 1 : 0;
	push.rightPanelOpen = IsRightPanelOpen() ? 1 : 0;

	vkCmdPushConstants(cmd, g_PipelineLayout, VK_SHADER_STAGE_FRAGMENT_BIT, 0, sizeof(push), &push);

	vkCmdDraw(cmd, 3, 1, 0, 0); // Draw fullscreen triangle covering the viewport
	vkCmdEndRenderPass(cmd);

	vkEndCommandBuffer(cmd);

	// Submit Queue
	VkSubmitInfo submitInfo {};
	submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
	VkSemaphore waitSemaphores[] = { g_ImageAvailableSemaphores[g_CurrentFrame] };
	VkPipelineStageFlags waitStages[] = { VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT };
	submitInfo.waitSemaphoreCount = 1;
	submitInfo.pWaitSemaphores = waitSemaphores;
	submitInfo.pWaitDstStageMask = waitStages;
	submitInfo.commandBufferCount = 1;
	submitInfo.pCommandBuffers = &cmd;
	VkSemaphore signalSemaphores[] = { g_RenderFinishedSemaphores[g_CurrentFrame] };
	submitInfo.signalSemaphoreCount = 1;
	submitInfo.pSignalSemaphores = signalSemaphores;

	vkQueueSubmit(g_Queue, 1, &submitInfo, g_InFlightFences[g_CurrentFrame]);

	// Present
	VkPresentInfoKHR presentInfo {};
	presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
	presentInfo.waitSemaphoreCount = 1;
	presentInfo.pWaitSemaphores = signalSemaphores;
	VkSwapchainKHR swapchains[] = { g_Swapchain };
	presentInfo.swapchainCount = 1;
	presentInfo.pSwapchains = swapchains;
	presentInfo.pImageIndices = &imageIndex;

	vkQueuePresentKHR(g_Queue, &presentInfo);

	g_CurrentFrame = (g_CurrentFrame + 1) % MAX_FRAMES_IN_FLIGHT;
}

} // namespace devilution

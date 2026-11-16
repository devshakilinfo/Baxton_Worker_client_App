import 'dart:io';

import 'package:baxton/core/urls/endpoint.dart';
import 'package:baxton/features/Admin_flow/taakbeheer/task_creation/models/employee_model.dart';
import 'package:baxton/features/Admin_flow/taakbeheer/task_creation/models/task_creation_model.dart';
import 'package:baxton/features/Admin_flow/taakbeheer/task_creation/models/task_type_model.dart';
import 'package:baxton/features/Admin_flow/taakbeheer/task_creation/views/employee_screen.dart';
import 'package:baxton/features/klant_flow/authentication/auth_service/auth_service.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

class TaskCreationController extends GetxController {
  final selectedEmployee = Rxn<Employee>();
  final taskTypes = <TaskType>[].obs;
  var selectedTaskType = RxnString(); // Use RxnString for null safety
  var selectedAssignee = ''.obs;
  var expertise = ''.obs;
  var selectedTime = ''.obs;
  var selectedImage = Rx<File?>(null);
  var selectedTaskTypeId = RxnString();

  final descriptionController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final locationController = TextEditingController();
  final dateController = TextEditingController();
  final emailController = TextEditingController();
  final postcodeController = TextEditingController();
  final describelocationController = TextEditingController();

  final timeController = TextEditingController(text: '11:00 uur');

  var preferredDate = DateTime.now().obs;

  void createTask() {
    final task = TaskCreationModel(
      taskType: selectedTaskType.value ?? '', // Use name for taskType
      description: descriptionController.text,
      clientName: nameController.text,
      clientPhone: phoneController.text,
      clientLocation: locationController.text,
      preferredDate: preferredDate.value,
      preferredTime: timeController.text,
      assignedTo: selectedAssignee.value,
      expertise: expertise.value,
    );

    debugPrint('========== 🛠️ Task Creation Data ==========');

    // Task fields
    debugPrint('📌 Selected Task Type: ${selectedTaskType.value}');
    debugPrint('📌 Selected Task Type ID: ${selectedTaskTypeId.value}');
    debugPrint('📝 Task Description: ${descriptionController.text}');
    debugPrint('👤 Customer Name: ${nameController.text}');
    debugPrint('📧 Customer Email: ${emailController.text}');
    debugPrint('📞 Customer Phone: ${phoneController.text}');
    debugPrint('📍 Customer Location: ${locationController.text}');
    debugPrint('🏷️ Postal Code: ${postcodeController.text}');
    debugPrint('🗺️ Describe Location: ${describelocationController.text}');
    debugPrint('📅 Preferred Date: ${dateController.text}');
    debugPrint('⏰ Preferred Time: ${selectedTime.value}');

    // Employee details
    final emp = selectedEmployee.value;
    if (emp != null) {
      debugPrint('✅ Selected Employee ID: ${emp.workerId}');
      debugPrint('✅ Selected Employee Name: ${emp.name}');
      debugPrint('✅ Selected Employee Role: ${emp.role}');
      debugPrint('✅ Selected Employee Expertise: ${emp.expertise}');
      debugPrint('✅ Selected Employee Image URL: ${emp.imageUrl}');
    } else {
      debugPrint('❌ No employee selected');
    }

    // Image details
    if (selectedImage.value != null) {
      debugPrint('🖼️ Selected Image Path: ${selectedImage.value!.path}');
    } else {
      debugPrint('🖼️ No image selected');
    }

    debugPrint('===========================================');

    debugPrint("Task Created: ${task.taskType}, for ${task.clientName}");
    Get.snackbar("Success", "Taak aangemaakt!");
  }

  void openEmployeeSelection() {
    Get.to(() => EmployeeScreen());
  }

  void cancel() {
    Get.back();
  }

  Future<List<TaskType>?> fetchTaskTypes() async {
    debugPrint('Starting fetchTaskTypes API call');
    await EasyLoading.show(
      status: 'Loading task types...',
      maskType: EasyLoadingMaskType.black,
    );

    try {
      debugPrint('Fetching authentication token');
      String? token = await AuthService.getToken();
      debugPrint('Retrieved token: $token');

      if (token == null || token.isEmpty) {
        debugPrint('Token validation failed: Token is null or empty');
        await EasyLoading.showError('Authentication token is missing');
        throw Exception('Token is not available');
      }

      const url = Urls.taskType;
      debugPrint('Sending GET request to API: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      debugPrint(
        'API response received with status code: ${response.statusCode}',
      );
      debugPrint('Raw API response: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('API call successful, parsing response body');
        final taskTypesList = taskTypeListFromJson(response.body);
        taskTypes.assignAll(taskTypesList);
        if (taskTypesList.isNotEmpty) {
          selectedTaskType.value = taskTypesList.first.name;
        } else {
          selectedTaskType.value = null;
        }
        debugPrint('Parsed ${taskTypesList.length} task types');
        await EasyLoading.showSuccess('Task types loaded successfully');
        return taskTypesList;
      } else {
        debugPrint('API call failed with status code: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        await EasyLoading.showError(
          'Failed to load task types: ${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('Error occurred while fetching task types: $e');
      await EasyLoading.showError('Error fetching task types: $e');
      return null;
    } finally {
      debugPrint('Cleaning up: Dismissing EasyLoading');
      await EasyLoading.dismiss();
    }
  }

  @override
  void onInit() {
    fetchTaskTypes();
    super.onInit();
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 800,
      );

      if (pickedFile != null) {
        selectedImage.value = File(pickedFile.path);
      }
    } catch (e) {
      debugPrint('Failed to pick image: $e');
      EasyLoading.showError('Failed to pick image: $e');
    }
  }

  Future<void> submitTaskToApi() async {
    try {
      await EasyLoading.show(status: 'Taak aanmaken...');

      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        EasyLoading.showError('Geen geldig token gevonden');
        return;
      }

      // ✅ Gather all data
      final emp = selectedEmployee.value;
      if (emp == null) {
        EasyLoading.showError('Geen werknemer geselecteerd');
        return;
      }

      final taskTypeId =
          selectedTaskTypeId.value; // 👈 Make sure you store this earlier
      if (taskTypeId == null || taskTypeId.isEmpty) {
        EasyLoading.showError('Geen taaktype geselecteerd');
        return;
      }

      // ✅ Build multipart request
      final url = Uri.parse(
        'https://freepik.softvenceomega.com/ts/admin/service-request/assign-task',
      );
      final request =
          http.MultipartRequest('POST', url)
            ..headers['Authorization'] = 'Bearer $token'
            ..fields['locationDescription'] = describelocationController.text
            ..fields['city'] = locationController.text
            ..fields['name'] = descriptionController.text
            ..fields['preferredTime'] =
                preferredDate.value.toUtc().toIso8601String()
            ..fields['preferredDate'] =
                preferredDate.value.toUtc().toIso8601String()
            ..fields['phoneNumber'] = phoneController.text
            ..fields['postalCode'] = postcodeController.text
            ..fields['workerId'] = emp.workerId
            ..fields['taskTypeId'] = taskTypeId
            ..fields['email'] = emailController.text
            ..fields['problemDescription'] =
                descriptionController
                    .text; // if you have a separate field use that

      // ✅ Add image if selected
      if (selectedImage.value != null) {
        final imageFile = selectedImage.value!;
        request.files.add(
          await http.MultipartFile.fromPath(
            'reqPhoto',
            imageFile.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      // ✅ Send request
      final response = await request.send();

      // ✅ Read response
      final responseBody = await response.stream.bytesToString();
      debugPrint('📡 API Response: $responseBody');

      if (response.statusCode == 200 || response.statusCode == 201) {
        EasyLoading.showSuccess('Taak succesvol aangemaakt!');
        debugPrint('✅ Task created successfully! $responseBody');
        clearForm();
        Get.back();
      } else {
        EasyLoading.showError('Fout: ${response.statusCode}');
        debugPrint('❌ Error creating task: $responseBody');
      }
    } catch (e) {
      debugPrint('❌ Exception: $e');
      EasyLoading.showError('Er is een fout opgetreden: $e');
    } finally {
      EasyLoading.dismiss();
    }
  }

  void clearForm() {
    // ✅ Clear all text fields
    descriptionController.clear();
    nameController.clear();
    emailController.clear();
    phoneController.clear();
    locationController.clear();
    postcodeController.clear();
    describelocationController.clear();
    dateController.clear();
    timeController.clear();

    // ✅ Clear selected values
    selectedTaskType.value = null;
    selectedTaskTypeId.value = ''; // make sure you have this variable
    selectedEmployee.value = null;
    selectedAssignee.value = '';
    expertise.value = '';
    selectedTime.value = '';

    // ✅ Clear image
    selectedImage.value = null;

    // ✅ Reset date to today
    preferredDate.value = DateTime.now();

    debugPrint('🧹 Form cleared successfully!');
  }
}

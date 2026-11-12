import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/services/snap_pipeline_service.dart';

void main() {
  group('SnapPipelineTask', () {
    test('reports correct running/done/failed states', () {
      final savingTask = SnapPipelineTask(
        homeworkId: 'hw-1',
        stage: SnapPipelineStage.saving,
        currentStep: 0,
      );
      expect(savingTask.isRunning, isTrue);
      expect(savingTask.isDone, isFalse);
      expect(savingTask.isFailed, isFalse);
      expect(savingTask.stepLabel, 'Sparar läxan …');

      final readingTask = SnapPipelineTask(
        homeworkId: 'hw-1',
        stage: SnapPipelineStage.reading,
        currentStep: 1,
      );
      expect(readingTask.isRunning, isTrue);
      expect(readingTask.stepLabel, 'Läser din läxa 👀');

      final doneTask = SnapPipelineTask(
        homeworkId: 'hw-1',
        stage: SnapPipelineStage.done,
        currentStep: 4,
      );
      expect(doneTask.isRunning, isFalse);
      expect(doneTask.isDone, isTrue);
      expect(doneTask.isFailed, isFalse);
      expect(doneTask.stepLabel, 'Klar!');

      final failedTask = SnapPipelineTask(
        homeworkId: 'hw-1',
        stage: SnapPipelineStage.failed,
        errorMsg: 'Ingen text',
      );
      expect(failedTask.isRunning, isFalse);
      expect(failedTask.isDone, isFalse);
      expect(failedTask.isFailed, isTrue);
      expect(failedTask.stepLabel, contains('Ingen text'));
    });

    test('service reports isRunning correctly', () {
      expect(SnapPipelineService.instance.isRunning('non-existent'), isFalse);
    });
  });
}

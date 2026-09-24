import 'package:crowd_beats_front/core/theme/app_theme.dart';
import 'package:crowd_beats_front/features/vote/vote_action.dart';
import 'package:crowd_beats_front/features/vote/vote_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget voteApp(TrackVoteState? action, VoidCallback onVote) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              VoteButton(
                trackTitle: 'Test Track',
                action: action,
                onVote: onVote,
              ),
              VoteFeedback(action: action),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('vote action represents actionable and terminal states', (
    tester,
  ) async {
    var submissions = 0;
    void submit() => submissions++;

    await tester.pumpWidget(voteApp(null, submit));
    await tester.tap(find.byTooltip('Vote for Test Track'));
    expect(submissions, 1);

    await tester.pumpWidget(
      voteApp(
        const TrackVoteState(
          phase: VotePhase.submitting,
          message: 'Submitting vote…',
        ),
        submit,
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      voteApp(
        const TrackVoteState(
          phase: VotePhase.accepted,
          message: 'Vote counted. 4 votes remaining.',
        ),
        submit,
      ),
    );
    expect(find.byTooltip('Voted for Test Track'), findsOneWidget);
    expect(find.text('Vote counted. 4 votes remaining.'), findsOneWidget);

    await tester.pumpWidget(
      voteApp(
        const TrackVoteState(
          phase: VotePhase.alreadyVoted,
          message: 'You already voted for this track.',
        ),
        submit,
      ),
    );
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('You already voted for this track.'), findsOneWidget);

    await tester.pumpWidget(
      voteApp(
        const TrackVoteState(
          phase: VotePhase.limitReached,
          message: 'You have reached this room’s vote limit.',
        ),
        submit,
      ),
    );
    await tester.tap(find.byTooltip('Vote for Test Track'));
    expect(submissions, 2);
    expect(
      find.text('You have reached this room’s vote limit.'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      voteApp(
        const TrackVoteState(
          phase: VotePhase.trackInactive,
          message: 'This track is no longer available for voting.',
        ),
        submit,
      ),
    );
    expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    expect(
      find.text('This track is no longer available for voting.'),
      findsOneWidget,
    );
  });
}

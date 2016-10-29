///////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////MIKROSKOPIE3//////////////////////////////////////////////
////////////////////////////////////////LUKASNOWOK///////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////




(
~getFFTData = {//use on frame data format
	arg filePath, time;
	var file, freq = List.new, ratio = List.new, amp = List.new, data, line;

	file = FileReader.read(filePath);
	line = (time*100)+5;
	data = file.at(line);
	data.removeAt(0);
	data.removeAt(1);

	data.do
	({
		arg element, index;
		if(index%3 == 1)
		{
			freq.add(element.asFloat);
		};
		if(index%3 == 2)
		{
			amp.add(element.asFloat);
		};
	});

	freq.do
	({
		arg element, index;
		ratio.add(element/freq.at(0));
	});

	[freq.asArray, ratio.asArray, amp.asArray];
};

/* not in use in this version (can be used interchangeably with Synth(\bpf) )
SynthDef(\zither,
	{
		arg buf, outBus, rate = 1, rateScale = 1, start = 0, amp = 0.1, group = 0, element;
		var sig, playhead, messageTrigger, bufLength, in, amount, amCoef, outSig;
		bufLength = BufFrames.kr(buf);
		playhead = Phasor.ar(0, BufRateScale.kr(buf)*(rate*rateScale), start, bufLength);
		messageTrigger = InRange.kr(playhead, bufLength*0.7, bufLength);
		sig = BufRd.ar(1, buf, playhead, 1, 4)*amp;
		sig = LPF.ar(sig, 5000);


		/*in = HPF.ar(sig, 100)*8;
		amount = 0.99; /////////////////////// experimental distortion
		amCoef= 2*amount/(1-amount);
		outSig = MidEQ.ar(LPF.ar((1+amCoef)*in/(1+(amCoef*in.abs)), 3900)*0.5, 120, 0.7, 8)*amp;*/


		Out.ar(outBus, LeakDC.ar(sig));

		SendReply.kr(messageTrigger, '/fading', [rate, amp, outBus, group, element]);

		FreeSelf.kr(InRange.kr(playhead, bufLength*0.99, bufLength));
	};
).add;
*/

SynthDef(\bpf,
	{
		arg
		outBus,
		buf,
		rate = 1,
		rateScale = 1,
		start = 0,
		amp = 0.1,
		group = 0,
		element,
		attack = 15,
		release = 30,
		q = 0.001;

		var sig, env, messageTrigger, freq = 102, duration = attack+release;

		messageTrigger = TDelay.kr(DC.kr(1), duration*0.999);

		env = EnvGen.kr(Env([0, amp, 0].flat, [attack, release], \sqr), 1, doneAction:2);

		rate = rate*rateScale;
		freq = freq*rate;
		sig = BPF.ar(PinkNoise.ar(q.reciprocal), freq, q, env);
		Out.ar(outBus, LeakDC.ar(sig)!2);

		SendReply.kr(messageTrigger, '/fading', [rate, amp, outBus, group, element]);
	};
).add;

SynthDef(\masterBus,
	{
		arg inBus, amp = 1, hpf, lpf;
		var input, sig;

		input = In.ar(inBus, 1);
		sig = [input, DelayC.ar(input, 0.5, 0.5, 1)];
		sig = Compander.ar(sig, sig, 0.9, 1, 0.7, 0.01, 0.2);
		sig = Limiter.ar(sig, 0.95);

		Out.ar(0, LeakDC.ar(sig));
	};
).add;

//////////////////////////////////////////////////////////////////////////////////
//variable initialisation
~fileList = PathName.new(".../mikroskopie/data/").entries; // set path to 'spectra'
~spectra = Array.newFrom([~getFFTData.value(~fileList.at(10).fullPath, 0.5), ~getFFTData.value(~fileList.at(11).fullPath, 0.5)]);
~spectrumProb = Array.newFrom([1, 0]); // Probability of choosing first/second spectrum
~currentSpectrum = 0;
//~ampThreshold = ~spectra.at(0).at(2).mean; // no partials with amplitude below threshold!
~numSynths = 184; // approx. number of active synths
~ampThreshold = 0;
~densityProb = Array.newFrom([0, 1, 0.5]); // Probability of triggering 0, 1 or 2 synths respectively
~outBus = Bus.audio(s, 1); // input bus from generators to master

~dummyArray = (0..1000);

~partialProb = Array.newFrom
([
	Array.newFrom(Env(Array.rand(4, 0.0, 1.0), 1!3, \sin).asSignal(~spectra.at(0).at(1).size)).normalizeSum,
	Array.newFrom(Env(Array.rand(4, 0.0, 1.0), 1!3, \sin).asSignal(~spectra.at(1).at(1).size)).normalizeSum
]);
//////////////////////////////////////////////////////////////////////////////////
"done initialising";
)



(
//////////////////////////////////////////////////////////////////////////////////
///spawning initial synths
~numSynths.do(
	{
		arg i;
		var bufnum;
		var group = 0;
		var size = ~spectra.at(group).at(1).size;
		var element = ~dummyArray.wchoose(~partialProb.at(group)); // weighted probability (~partialProb)
		var rate;
		var amp = ~spectra.at(group).at(2).at(element);

		/*
		///////////////////// 
		//amplitude threshold
		while({amp < ~ampThreshold},
		{
		element = dummyArray.wchoose(~partialProb.at(group));
		amp = ~spectra.at(group).at(2).at(element);
		}
		);
		/////////////////////
		*/
		rate = ~spectra.at(group).at(1).at(element);

		{
			rrand(10, 35).wait;
			Synth
			(\bpf,
				[
					\buf, 30,
					\outBus, ~outBus,//number of channels
					\rate, rate,
					\rateScale, 0.61,
					\start, 0,
					\amp, amp*0.5,
					\element, element,

					\q, 0.00014*(rate*2.34), // higher partial = wider bandwidth
					\attack, 40,
					\release, 30,
				]
			);
		}.fork;
	};
);
//////////////////////////////////////////////////////////////////////////////////

//trigger master bus (compression/limiting)
Synth(\masterBus, [\inBus, ~outBus], addAction: \addToTail);

//////////////////////////////////////////////////////////////////////////////////
//retrigger routine
OSCFunc(
	{
		arg mes;
		//"fading ".post;
		([0,1,2].wchoose(~densityProb)).do // control density by spawing more or less synths
		(
			{
				var group = [0, 1].wchoose(~spectrumProb.normalizeSum); // choose between first and second spectrum

				var size = ~spectra.at(group).at(1).size;
				var element = ~dummyArray.wchoose(~partialProb.at(group)); // weighted probability (~partialProb)
				var rate = ~spectra.at(group).at(1).at(element);
				var amp = ~spectra.at(group).at(2).at(element);

				/*
				/////////////////////
				//amplitude threshold
				while({amp < ~ampThreshold},
				{
				element = dummyArray.wchoose(~partialProb.at(group));
				amp = ~spectra.at(group).at(2).at(element);
				}
				); //danger!!! infLoop
				/////////////////////

				rate = ~spectra.at(group).at(1).at(element);
				*/
				{
					rrand(0, 30).wait;
					Synth
					(\bpf,
						[
							\buf, 30,
							\outBus, ~outBus,
							\rate, rate,
							\rateScale, 0.61,
							\amp, amp*0.5,
							\group, group,
							\element, element,

							\q, 0.00014*(rate*2.34), // higher partial = higher bandwidth
							\attack, 60.rand+20,
							\release, 40.rand+20,
						]
					).postln;
				}.fork;
				//element.postln;
				//group.postln;
			};
		);
	}, '/fading'
);
//////////////////////////////////////////////////////////////////////////////////



Routine
{
	inf.do(
		{
			arg count;
			var clock = 1;
			var fadeTime = 25; //minutes to fade between two spectra
			var parialFade;
			////////////////////////////////////
			//crossfade current and next spectrum
			~spectrumProb.put(1, ((count/((fadeTime/clock)*60)).fold(0, 1)).lincurve(0, 1, 0, 1, -1));
			~spectrumProb.put(0, (~spectrumProb.at(1)).linlin(0,1,1,0));
			////////////////////////////////////

			////////////////////
			//load next spectrum
			if (~spectrumProb.at(0) == 0)
			{
				{
					var newSpectrum = ~fileList.size.rand;
					~currentSpectrum = ~currentSpectrum+1;
					~spectra.put(0, ~getFFTData.value(~fileList.wrapAt(newSpectrum).fullPath, 0.5));
					s.sync;
					~partialProb.put(0, ~partialProb.at(0).resamp1(~spectra.at(0).at(1).size).normalizeSum); //resample partialProb
					postf("%:%:%:% :: % \n", (count/86400).floor,(count/3600).floor%24,(count/60).floor%60,count%60,"new spectrum");
				}.fork;
			};
			if (~spectrumProb.at(1) == 0)
			{
				{
					var newSpectrum = ~fileList.size.rand;
					~currentSpectrum = ~currentSpectrum+1;
					~spectra.put(1, ~getFFTData.value(~fileList.wrapAt(newSpectrum).fullPath, 0.5));
					s.sync;
					~partialProb.put(1, ~partialProb.at(1).resamp1(~spectra.at(1).at(1).size).normalizeSum); //resample partialProb
					postf("%:%:%:% :: % \n", (count/86400).floor,(count/3600).floor%24,(count/60).floor%60,count%60,"new spectrum");
				}.fork;
			};
			////////////////////

			/////////////////////////////
			//generate partial probabilities
			if ([true, false].wchoose([1, 200].normalizeSum))
			{
				var size = 4;
				~partialProb.put(0, Array.newFrom(Env(Array.rand(size, 0, 1), 1!(size-1), \sin).asSignal(~spectra.at(0).at(1).size)).normalizeSum);
				~partialProb.put(1, Array.newFrom(Env(Array.rand(size, 0, 1), 1!(size-1), \sin).asSignal(~spectra.at(1).at(1).size)).normalizeSum);
				postf("%:%:%:% :: % \n", (count/86400).floor,(count/3600).floor%24,(count/60).floor%60,count%60,"new partial probability");
			};
			/////////////////////////////

			////////////////////////////
			//change amplitude threshold
			////////////////////////////

			////////////////////////////////
			//control number of active synths
			case
			{s.numSynths > ~numSynths} {~densityProb = [1, 0.5, 0].normalizeSum} // lower density if more than numSynths active
			{s.numSynths.exclusivelyBetween(~numSynths*0.8, ~numSynths*1.2)} {~densityProb = [0, 1, 0.5].normalizeSum}
			{s.numSynths < ~numSynths} {~densityProb = [0, 0.5, 1].normalizeSum} // higher density if less than numSynths active
			{s.numSynths == 0} {"dead".postln};
			////////////////////////////////

			clock.wait;
		}
	);
}.play)



///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//Alternative Intro
(
var group = 0;
var amps = ~spectra.at(group).at(2);
Routine
{
	50.do(
		{
			arg i;
			var bufnum = 30;
			var element = amps.maxIndex;
			var rate = ~spectra.at(group).at(1).at(element);
			var amp = ~spectra.at(group).at(2).at(element);
			Synth
			(\bpf,
				[
					\buf, bufnum,
					\out, 0,
					\rate, rate,
					\rateScale, 1,
					\start, 0,
					\amp, amp*2,
					\element, element,
					\duration, 220.rand+300,
				]
			);
			amps.removeAt(element);
			element.postln;
			40.wait;
		};
)}.play;
)

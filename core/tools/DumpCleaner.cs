using System;
using System.IO;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace PortableDumpCleaner
{
    class Program
    {
        class ImageRange
        {
            public string Name;
            public int StartTDI;
            public int EndTDI;
        }

        class CutRange
        {
            public int S;
            public int E;
        }

        static void Main(string[] args)
        {
            if (args.Length < 2)
            {
                Console.WriteLine("Usage: DumpCleaner.exe <input_dump.cs> <output_cleaned.cs>");
                return;
            }

            string inputFile = args[0];
            string outputFile = args[1];

            if (!File.Exists(inputFile))
            {
                Console.WriteLine("[Error] Input file not found: " + inputFile);
                return;
            }

            Console.WriteLine("[*] Starting fast C# Dump Cleaner...");

            // 1. Define noise images to cut based on user's list
            HashSet<int> cutImages = new HashSet<int> {
                1, 3, 4, 5, 6, 8, 9, 11, 12, 14, 16, 17, 18, 19, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 41, 43, 44, 46, 47, 49, 50, 51, 55, 56, 57, 58, 59, 60, 62, 63, 64, 65, 66, 67, 68, 69, 71, 72, 73, 74, 75, 76, 77, 79, 80, 81, 82, 83, 84, 85, 86, 89, 90, 91, 92, 93, 94, 95, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 134, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 147, 148, 149, 150, 151, 153, 154, 155, 156, 157, 158, 159, 160, 161
            };

            // Keep PS.Logs.Cheats.dll (152) as requested
            cutImages.Remove(152);

            // Structure to hold TypeDefIndex ranges
            var imageMap = new Dictionary<int, ImageRange>();
            int lastImageIdx = -1;
            int lastStartTDI = -1;

            Console.WriteLine("[1/3] Parsing headers...");

            // Pass 1: Parse the header to build the Image -> TypeDefIndex map
            using (var reader = new StreamReader(inputFile))
            {
                string line;
                int lineCount = 0;
                while ((line = reader.ReadLine()) != null && lineCount < 200)
                {
                    lineCount++;
                    var match = Regex.Match(line, @"^// Image (\d+): (.+?) - (\d+)");
                    if (match.Success)
                    {
                        int imgIdx = int.Parse(match.Groups[1].Value);
                        string imgName = match.Groups[2].Value.Trim();
                        int startTDI = int.Parse(match.Groups[3].Value);

                        if (lastImageIdx >= 0)
                        {
                            var prev = imageMap[lastImageIdx];
                            imageMap[lastImageIdx] = new ImageRange { Name = prev.Name, StartTDI = prev.StartTDI, EndTDI = startTDI - 1 };
                        }

                        imageMap[imgIdx] = new ImageRange { Name = imgName, StartTDI = startTDI, EndTDI = int.MaxValue };
                        lastImageIdx = imgIdx;
                        lastStartTDI = startTDI;
                    }
                }
            }

            // Build fast cut ranges
            var cutRanges = new List<CutRange>();
            foreach (var imgIdx in cutImages)
            {
                if (imageMap.ContainsKey(imgIdx))
                {
                    var entry = imageMap[imgIdx];
                    cutRanges.Add(new CutRange { S = entry.StartTDI, E = entry.EndTDI });
                }
            }
            cutRanges.Sort((a, b) => a.S.CompareTo(b.S));

            Console.WriteLine("   Cutting " + cutImages.Count + " noisy framework modules.");
            Console.WriteLine("[2/3] Stream parsing and stripping file...");

            int totalLines = 0;
            int keptLines = 0;

            Regex typeDefPattern = new Regex(@"//\s*TypeDefIndex\s*:\s*(\d+)");
            // Anonymous patterns, DisplayClass, generic structs, embedded attributes
            Regex anonClassPattern = new Regex(@"^(internal|private|public)?\s*(sealed\s+)?(class|struct)\s+(<>f__AnonymousType\d+|<>c__DisplayClass\d+|<\w+>d__\d+|<>c|<Module>)\b");

            bool skipBlock = false;
            bool inGenericComment = false;
            bool skipAnonMode = false;
            int skipAnonDepth = 0;

            using (var reader = new StreamReader(inputFile))
            using (var writer = new StreamWriter(outputFile))
            {
                string line;
                while ((line = reader.ReadLine()) != null)
                {
                    totalLines++;

                    // 1. GenericInstMethod Block skipping
                    if (inGenericComment)
                    {
                        if (line.Contains("*/")) inGenericComment = false;
                        continue;
                    }
                    if (line.Contains("/* GenericInstMethod"))
                    {
                        if (!line.Contains("*/")) inGenericComment = true;
                        continue;
                    }

                    // 2. Class Block skipping by TypeDefIndex
                    var tdiMatch = typeDefPattern.Match(line);
                    if (tdiMatch.Success)
                    {
                        int newTDI = int.Parse(tdiMatch.Groups[1].Value);
                        skipBlock = false;
                        foreach (var r in cutRanges)
                        {
                            if (newTDI >= r.S && newTDI <= r.E) { skipBlock = true; break; }
                            if (r.S > newTDI) break; // Optimization
                        }
                        skipAnonMode = false;
                        skipAnonDepth = 0;
                    }

                    if (skipBlock) continue;

                    // 3. Anonymous/Compiler Generated Classes
                    if (!skipAnonMode && anonClassPattern.IsMatch(line))
                    {
                        skipAnonMode = true;
                        skipAnonDepth = 0;
                        continue;
                    }

                    if (skipAnonMode)
                    {
                        foreach (char c in line)
                        {
                            if (c == '{') skipAnonDepth++;
                            else if (c == '}')
                            {
                                skipAnonDepth--;
                                if (skipAnonDepth <= 0)
                                {
                                    skipAnonMode = false;
                                    break;
                                }
                            }
                        }
                        continue;
                    }

                    // 4. Strip Noise Attributes and NameSpaces
                    string stripped = line.Trim();
                    if (stripped == "// Namespace: " ||
                        stripped == "[DebuggerBrowsable(0)]" ||
                        stripped == "[DebuggerBrowsable(DebuggerBrowsableState.Never)]" ||
                        stripped == "[DebuggerHidden]" ||
                        stripped == "[DebuggerStepThrough]" ||
                        stripped == "[CompilerGenerated]" ||
                        stripped == "[Embedded]" ||
                        stripped == "[IteratorStateMachine]" ||
                        stripped.StartsWith("[IteratorStateMachine(typeof(") ||
                        stripped.StartsWith("[Usage("))
                    {
                        continue; // Skip these completely
                    }
                    
                    // 5. Trim heavy RVA/Offset comments, we just want the methods
                    // Example: // RVA: 0x46C5548 Offset: 0x46C1548 VA: 0x46C5548
                    if (stripped.StartsWith("// RVA: 0x") || string.IsNullOrEmpty(stripped))
                    {
                        continue;
                    }

                    writer.WriteLine(line);
                    keptLines++;
                }
            }

            Console.WriteLine("[3/3] Done!");
            Console.WriteLine("   Reduced " + totalLines + " lines to " + keptLines + " lines.");
            
            // File size calculation
            long origSize = new FileInfo(inputFile).Length;
            long newSize = new FileInfo(outputFile).Length;
            double cutPct = (1.0 - (double)newSize / origSize) * 100;
            Console.WriteLine("   Size reduced by " + cutPct.ToString("F1") + "% (From " + (origSize / 1024 / 1024) + "MB to " + (newSize / 1024 / 1024) + "MB)");
        }
    }
}

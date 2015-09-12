<%@ WebHandler Language="C#" Class="Markdown" %>

using System;
using System.Web;
using System.Net;
using System.Text.RegularExpressions;

public class Markdown : IHttpHandler
{
    private static Regex _regex = new Regex("\\s(src|href)=(\"|')(?!https?://)(?<path>[^\"']+)\\2", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    public static Regex rxExtractLanguage = new Regex("^({{(.+)}}[\r\n])", RegexOptions.Compiled);

    public void ProcessRequest(HttpContext context)
    {
        context.Response.ContentType = "text/html";

        Uri url;
        if (!Uri.TryCreate(context.Request.QueryString["url"], UriKind.Absolute, out url))
            return;

        try
        {
            string content = DownloadFile(url);

            var result = RenderMarkdown(content);

            result = MakeAbsolute(result, url);

            context.Response.Write(result);
        }
        catch (Exception)
        {
            context.Response.Write("The markdown url could not be resolved.");
            context.Response.Status = "404 Not Found";
        }
    }

    private static string MakeAbsolute(string result, Uri url)
    {
        foreach (Match match in _regex.Matches(result))
        {
            string relative = match.Groups["path"].Value;
            string absolute = GetAbsoluteRoot(url) + "/" + relative;
            result = result.Replace(relative, absolute);
        }

        return result;
    }

    private static string GetAbsoluteRoot(Uri url)
    {
        int index = url.AbsoluteUri.LastIndexOf('/') + 1;

        return url.AbsoluteUri.Substring(0, index);
    }

    private static string DownloadFile(Uri url)
    {
        using (WebClient client = new WebClient())
        {
            return client.DownloadString(url);
        }
    }

    private static string RenderMarkdown(string content)
    {
        var markdown = new MarkdownDeep.Markdown();
        markdown.ExtraMode = true;
        markdown.SafeMode = false;
        markdown.FormatCodeBlock = FormatCodePrettyPrint;

        content = content.Replace("```", "~~~");

        // Change the fenced code block language for the markdown.FormatCodeBlock method
        content = Regex.Replace(content, @"(~~~\s?)(?<lang>[^\s]+)", "~~~\r{{${lang}}}");

        // Issue with MarkdownDeep reported here https://github.com/toptensoftware/markdowndeep/issues/63
        foreach (Match match in Regex.Matches(content, "( {0,3}>)+( {0,3})([^\r\n]+)", RegexOptions.Multiline))
        {
            content = content.Replace(match.Value, match.Value + "  ");
        }

        var result = markdown
                    .Transform(content)
                    .Replace("[ ] ", "<input type=\"checkbox\" disabled /> ")
                    .Replace("[x] ", "<input type=\"checkbox\" disabled checked /> ");

        return result;
    }

    private static string FormatCodePrettyPrint(MarkdownDeep.Markdown m, string code)
    {
        // Try to extract the language from the first line
        var match = rxExtractLanguage.Match(code);
        string language = string.Empty;

        if (match.Success)
        {
            var g = match.Groups[2];
            language = g.ToString().Trim().ToLowerInvariant();

            code = code.Substring(match.Groups[1].Length);
        }

        if (string.IsNullOrEmpty(language))
        {
            var d = m.GetLinkDefinition("default_syntax");
            if (d != null)
                language = d.title;
        }

        // Common replacements
        if (language.Equals("C#", StringComparison.OrdinalIgnoreCase))
            language = "cs";
        else if (language.Equals("csharp", StringComparison.OrdinalIgnoreCase))
            language = "cs";
        else if (language.Equals("C++", StringComparison.OrdinalIgnoreCase))
            language = "cpp";

        if (string.IsNullOrEmpty(language))
        {
            return "<pre><code>" + code + "</code></pre>\n";
        }
        else
        {
            return "<pre class=\"prettyprint lang-" + language + "\"><code>" + code + "</code></pre>\n";
        }
    }

    public bool IsReusable
    {
        get
        {
            return false;
        }
    }

}
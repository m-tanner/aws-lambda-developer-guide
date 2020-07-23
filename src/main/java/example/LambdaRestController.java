package example;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.view.RedirectView;

@RestController
public class LambdaRestController {

  @Autowired
  private Extractor Extractor;

  @RequestMapping(path = "some_path", method = RequestMethod.GET)
  public RedirectView extractData(
      @RequestParam(name = "requestParam1", required = false) Long requestParam1,
      @RequestParam(name = "requestParam1", required = false) Long requestParam2) {

    return new RedirectView(Extractor.extract(requestParam1, requestParam2));
  }
}
